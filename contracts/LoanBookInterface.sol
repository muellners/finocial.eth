pragma solidity^0.5.0;

contract LoanBookInterface {

    function getCollateralPrice(address _collateral) external returns(uint256);

}
