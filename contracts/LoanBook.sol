pragma solidity^0.5.0;

import './CollateralBook.sol';
import './LoanContract.sol';
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract LoanBook is Ownable, Pausable, CollateralBook {

  address[] public loans;

  constructor() public {

  }

  event LoanOfferCreated(address, address);
  event LoanRequestCreated(address, address);

  /**
  * @dev create new Loan offer for borrower
  */
  function createNewLoanOffer(uint256 _loanAmount, uint128 _duration, bytes32[3][] memory _collateralsMetadata)
    public payable returns(address) {

      //require(msg.value >= _loanAmount, "Sufficient funds not transferred");

      for(uint i=0; i< _collateralsMetadata.length; i++){
        require(collaterals[address(bytes20(_collateralsMetadata[i][0]))].isActive != false, "Collateral Not Supported");
      }

      LoanContract loanContract = new LoanContract(_loanAmount, _duration, address(0), msg.sender, LoanContract.LoanStatus.INACTIVE);

      loanContract.setCollateralMetaData(_collateralsMetadata);

      loans.push(address(loanContract));

      // if(!transferFundsToLoanContract(address(loanContract))){
      //     emit LoanCreationFailed(msg.sender);
      //     revert();
      // }

      emit LoanOfferCreated(msg.sender, address(loanContract));

      return address(loanContract);
  }

  /**
  * @dev create new Loan request for lender
  */
  function createNewLoanRequest(uint256 _loanAmount, uint128 _duration, bytes32[3][] memory _collateralsMetadata)
    public payable returns(address) {

      require(_collateralsMetadata.length == 1, "Not supported");
      require(collaterals[address(bytes20(_collateralsMetadata[0][0]))].isActive != false, "Collateral Not Supported");

      LoanContract loanContract = new LoanContract(_loanAmount, _duration, msg.sender, address(0), LoanContract.LoanStatus.INACTIVE);

      _collateralsMetadata[0][1] = bytes32(collaterals[address(bytes20(_collateralsMetadata[0][0]))].ltvRatio);

      loanContract.setCollateralMetaData(_collateralsMetadata);

      loans.push(address(loanContract));

      emit LoanRequestCreated(msg.sender, address(loanContract));

      return address(loanContract);
  }

  /**
  * @dev transfer funds to loan contract
  */
  // function transferFundsToLoanContract(address _loanContractAddress) private returns(bool) {
  //
  //   address(uint160(_loanContractAddress)).transfer(msg.value);
  //
  //   return true;
  // }

  function getAllLoans() public view returns(address[] memory) {
    return loans;
  }


}
