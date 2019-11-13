pragma solidity ^0.5.0;

import "./libs/LoanMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./LoanBookInterface.sol";

contract LoanContract {

  using SafeMath for uint256;

  uint256 constant PLATFORM_FEE_RATE = 100;
  address payable constant WALLET_1 = 0x88347aeeF7b66b743C46Cb9d08459784FA1f6908;
  uint256 constant SOME_THINGS = 105;
  address admin = 0x95FfeBC06Bb4b7DeDfF961769055C335542E1dBF;
  address public LoanBookAddress;

    enum LoanStatus {
        INACTIVE,
        OFFER,
        REQUEST,
        ACTIVE,
        REPAID
    }

    enum CollateralStatus {
        WAITING,
        ARRIVED,
        RETURNED
    }

    struct CollateralData {

        address collateralAddress;
        uint256 collateralAmount;
        uint256 collateralPrice; // will have to subscribe to oracle
        uint256 ltv;
        CollateralStatus collateralStatus;
    }

    struct LoanData {

        uint256 loanAmount;
        uint256 interestRate; // will be updated on acceptance in case of loan offer
        uint128 duration;
        uint256 createdOn;
        uint256 startedOn;
        mapping(uint256 => address) repayments;
        address payable borrower;
        address payable lender;
        uint256 repaidAmount;
        uint256 liquidatedAmount;
        LoanStatus loanStatus;
        CollateralData collateral; // will be updated on accepance in case of loan offer
    }

    bytes32[3][] acceptedCollateralsMetadata;

    LoanData loan;

    event CollateralTransferToLoanFailed(address, uint256);
    event CollateralTransferToLoanSuccessful(address, uint256, uint256);
    event FundTransferToLoanSuccessful(address, uint256);
    event FundTransferToBorrowerSuccessful(address, uint256);
    event LoanRepaid(address, uint256);
    event LoanStarted(uint256 _value); // watch for this event
    event CollateralTransferReturnedToBorrower(address, uint256);
    event CollateralClaimedByLender(address, uint256);
    event CollateralSentToLenderForDefaultedRepayment(uint256,address,uint256);
    event LoanContractUpdated(uint256, address, uint256, uint256, uint256);

    modifier OnlyBorrower {
        require(msg.sender == loan.borrower, "Only OnlyBorrower Authorised");
        _;
    }

     modifier OnlyAdmin {
        require(msg.sender == admin, "Only Admin Authorised");
        _;
    }

    modifier OnlyLender {
        require(msg.sender == loan.lender, "Only Lender Authorised");
        _;
    }

    modifier OnlyLoanBook {
        require(msg.sender == LoanBookAddress, "Only LoanBook Authorised");
        _;
    }



    constructor(uint256 _loanAmount, uint128 _duration,
      address _borrower, address _lender, LoanStatus _loanstatus) public {
        loan.loanAmount = _loanAmount;
        loan.duration = _duration;
        loan.createdOn = now;
        loan.borrower = address(uint160(_borrower));
        loan.lender = address(uint160(_lender));
        loan.loanStatus = _loanstatus;
        loan.collateral.collateralStatus = CollateralStatus.WAITING;
        LoanBookAddress = msg.sender;
    }

    function setCollateralMetaData(bytes32[3][] memory _collateralsMetadata) public OnlyLoanBook {
        acceptedCollateralsMetadata = _collateralsMetadata;
    }

    function getLoanData() view public returns (
        uint256 _loanAmount, uint128 _duration, uint256 _interestRate,
        uint256 createdOn, LoanStatus _loanStatus, bytes32[3][] memory _collateralsMetadata,
        address _collateralAddress, uint256 _collateralAmount, CollateralStatus _collateralStatus,
        address _borrower, address _lender) {

        return (loan.loanAmount, loan.duration, loan.interestRate,
                loan.createdOn, loan.loanStatus, acceptedCollateralsMetadata,
                loan.collateral.collateralAddress, loan.collateral.collateralAmount, loan.collateral.collateralStatus,
                loan.borrower, loan.lender);
    }

    function acceptLoanOffer() public {

        require(loan.loanStatus == LoanStatus.OFFER, "Invalid state change");

        loan.borrower = msg.sender;

    }


    function transferCollateralToLoan(address _collateral) public OnlyBorrower  {

      //add some check when transfer happens for loan offer(do we need to check if funds are transferred before this)?
      require(loan.collateral.collateralStatus == CollateralStatus.WAITING, 'Invalid state change');
      require(_collateral != address(0), "Non-valid collateral address");

      bytes32[3] memory collateralMetadata = validateCollateralAcceptance(_collateral);

      require(address(bytes20(collateralMetadata[0])) != address(0), "Non-acceptable collateral");

      IERC20 ERC20 = IERC20(_collateral);

      uint256 ltvRatio = uint256(collateralMetadata[1]);

      uint256 collateralPrice = LoanBookInterface(LoanBookAddress).getCollateralPrice(_collateral);

      uint256 collateralValue = LoanMath.calculateRequiredCollateralValue(loan.loanAmount, ltvRatio);

      uint256 collateralAmount = LoanMath.calculateCollateralAmount(collateralValue, collateralPrice);


      if(collateralAmount > ERC20.allowance(msg.sender, address(this))) {
          //emit CollateralTransferFailed(msg.sender);
          revert("Approved token amount is not Sufficient");
      }

      loan.interestRate = uint256(collateralMetadata[2]);

      loan.collateral.collateralAmount = collateralAmount;
      loan.collateral.collateralPrice = collateralPrice;
      loan.collateral.collateralStatus = CollateralStatus.ARRIVED;

      ERC20.transferFrom(msg.sender, address(this), collateralAmount);

      if(address(this).balance >= loan.loanAmount){
        loan.borrower.transfer(loan.loanAmount);
        loan.loanStatus = LoanStatus.ACTIVE;
        loan.startedOn = now;
      } else {
        loan.loanStatus = LoanStatus.REQUEST;
      }

      emit CollateralTransferToLoanSuccessful(msg.sender, loan.collateral.collateralAmount, loan.collateral.collateralPrice);

    }

    function validateCollateralAcceptance(address _collateral) internal view returns(bytes32[3] memory) {

      for(uint i=0; i<acceptedCollateralsMetadata.length; i++) {
        if(_collateral == address(bytes20(acceptedCollateralsMetadata[i][0])))
          return acceptedCollateralsMetadata[i];
      }
    }


    function transferFundsToLoanContract() public payable OnlyLender {

      require(loan.loanStatus == LoanStatus.INACTIVE, "Invalid state change");
      require(msg.value >= loan.loanAmount, "Sufficient funds not transferred");

      loan.loanStatus = LoanStatus.OFFER;

      emit FundTransferToLoanSuccessful(msg.sender, msg.value);

    }

     function approveLoanRequest() public payable {

          require(loan.loanStatus == LoanStatus.REQUEST, "Invalid state change");

          require(msg.value >= loan.loanAmount, "Sufficient funds not transferred");

          loan.lender = msg.sender;

          loan.loanStatus = LoanStatus.ACTIVE;

          loan.startedOn = now;

          loan.borrower.transfer(loan.loanAmount);

          emit FundTransferToBorrowerSuccessful(loan.borrower, loan.loanAmount);
    }

    function checkRepaymentStatus(uint256 _repaymentNumber) public view returns(address){
      //can we send all repayments data over here by iterating over the mapping
      return loan.repayments[_repaymentNumber];
    }

    function getCurrentRepaymentNumber() view public returns(uint256) {
      return LoanMath.getRepaymentNumber(loan.startedOn, loan.duration);
    }

    function getRepaymentAmount(uint256 repaymentNumber) view public returns(uint256 amount, uint256 monthlyInterest, uint256 fees){

        uint256 totalLoanRepayments = LoanMath.getTotalNumberOfRepayments(loan.duration);

        monthlyInterest = LoanMath.getAverageMonthlyInterest(loan.loanAmount, loan.interestRate, totalLoanRepayments);

        if(repaymentNumber == 1)
            fees = LoanMath.getPlatformFeeAmount(loan.loanAmount, PLATFORM_FEE_RATE);
        else
            fees = 0;

        amount = LoanMath.calculateRepaymentAmount(loan.loanAmount, monthlyInterest, fees, totalLoanRepayments);

        return (amount, monthlyInterest, fees);
    }



    function repayLoan() public payable {

            require(now <= loan.startedOn + loan.duration * 1 minutes, "Loan Duration Expired");

            uint256 repaymentNumber = LoanMath.getRepaymentNumber(loan.startedOn, loan.duration);

            require(loan.repayments[repaymentNumber] == address(0), "Cannot repay loan");

            (uint256 amount, , uint256 fees) = getRepaymentAmount(repaymentNumber);

            uint256 requiredRepaymentAmount = amount.sub(loan.liquidatedAmount);

            require(msg.value >= amount, "Required amount not transferred");

            if(fees != 0){
                transferToWallet1(fees);
            }
            uint256 toTransfer = requiredRepaymentAmount.sub(fees);

            //loan.repaidAmount = amount;

            loan.repayments[repaymentNumber] = loan.borrower;

            loan.lender.transfer(toTransfer);

           // should log particular repaymentNumber paid instead
            emit LoanRepaid(msg.sender, amount);
    }

  function transferToWallet1(uint256 fees) private {
      WALLET_1.transfer(fees);
  }

  function liquidateCollateral() public OnlyLender {

        require(now < loan.startedOn + loan.duration * 1 minutes, "Loan is not Active");


        uint256 currentCollateralPrice = LoanBookInterface(LoanBookAddress).getCollateralPrice(loan.collateral.collateralAddress);

        require(LoanMath.checkCollateralLiquidation(loan.loanAmount, loan.collateral.collateralAmount, currentCollateralPrice), "Liquidation not allowed");

        loan.liquidatedAmount = LoanMath.getLiquidationAmount(loan.loanAmount);

        uint256 collateralAmount = LoanMath.calculateCollateralAmount(loan.liquidatedAmount, currentCollateralPrice);

        loan.collateral.collateralAmount = loan.collateral.collateralAmount.sub(collateralAmount);

        loan.collateral.collateralPrice = currentCollateralPrice;


        IERC20 ERC20 = IERC20(loan.collateral.collateralAddress);

        ERC20.transfer(msg.sender, collateralAmount);

        // Add event here
    }



    function returnCollateralToBorrower() public OnlyBorrower {

        require(now > loan.startedOn + loan.duration * 1 minutes, "Loan Still Active");

        require(loan.collateral.collateralAmount > 0, "Nothing to return");

        require(loan.collateral.collateralStatus != CollateralStatus.RETURNED, "Already returned collateral");

        IERC20 ERC20 = IERC20(loan.collateral.collateralAddress);

        uint256 totalLoanRepayments = LoanMath.getTotalNumberOfRepayments(loan.duration);

        uint256 collateralValueToDeduct = 0;

        for(uint i=1; i<=totalLoanRepayments; i++){

            if(loan.repayments[i] == address(0)){

                (uint256 amount, ,) = getRepaymentAmount(i);

                collateralValueToDeduct += amount;
            }

        }

        uint256 collateralAmountToDeduct = LoanMath.calculateCollateralAmount(collateralValueToDeduct, loan.collateral.collateralPrice);

        loan.collateral.collateralAmount -= collateralAmountToDeduct;

        loan.collateral.collateralStatus = CollateralStatus.RETURNED;

        ERC20.transfer(msg.sender, loan.collateral.collateralAmount.sub(collateralAmountToDeduct));

        emit CollateralTransferReturnedToBorrower(msg.sender, loan.collateral.collateralAmount.sub(collateralAmountToDeduct));

    }

  function claimCollateralOnDefault(uint256 _repaymentNumber) public OnlyLender {

         uint256 totalLoanRepayments = LoanMath.getTotalNumberOfRepayments(loan.duration);

         require(_repaymentNumber > 0 && _repaymentNumber <= totalLoanRepayments, "Invalid repayment number");

         require(loan.repayments[_repaymentNumber] == address(0), "Cannot claim collateral");

         require(now > LoanMath.getRepaymentDate(loan.startedOn, _repaymentNumber), "Invalid claim");

         (uint256 amount, , uint256 fees) = getRepaymentAmount(_repaymentNumber);

         //uint256 currentCollateralPrice = LoanBookInterface(LoanBookAddress).getCollateralPrice(loan.collateral.collateralAddress);

         uint256 collateralAmountToTransfer = LoanMath.calculateCollateralAmount(amount, loan.collateral.collateralPrice);

         uint256 collateralAmountForWallet = LoanMath.calculateCollateralAmount(fees, loan.collateral.collateralPrice);

         uint256 collateralAmountForLender = collateralAmountToTransfer.sub(collateralAmountForWallet);

         loan.collateral.collateralAmount = loan.collateral.collateralAmount.sub(collateralAmountToTransfer);

         IERC20 ERC20 = IERC20(loan.collateral.collateralAddress);

         loan.repayments[_repaymentNumber] = loan.lender;

         if(fees != 0){

             ERC20.transfer(WALLET_1, collateralAmountForWallet);

         }

         ERC20.transfer(msg.sender, collateralAmountForLender);

         emit CollateralClaimedByLender(msg.sender, collateralAmountToTransfer);
     }
}
