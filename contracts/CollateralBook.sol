pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract CollateralBook is Ownable {

  struct collateral {
    uint256 price;
    uint256 ltvRatio;
    bool isActive;
  }

  mapping(address => collateral) public collaterals;

  constructor() public {

  }

  /**
  * @dev add address of collateral to list of supported collaterals using
  * collateral contract address as identifier in mapping
  */
  function addNewCollateral(address _address, uint256 _price, uint256 _ltvRatio) public onlyOwner returns(bool) {
    require(collaterals[_address].isActive == false, "Collateral Already Added");
    collaterals[_address].isActive = true;
    collaterals[_address].price = _price;
    collaterals[_address].ltvRatio = _ltvRatio;
    return true;
  }

  /**
  * @dev remove collateral contract address we no more support
  */
  function removeCollateral(address _address) public onlyOwner returns(bool) {
    require(collaterals[_address].isActive != false, "Collateral Already Removed");
    delete(collaterals[_address]);

    return true;
  }

  function updateCollateralPrice(address _address, uint256 _price) public onlyOwner returns(bool) {

    require(collaterals[_address].isActive != false, "Collateral Not Available");

    collaterals[_address].price = _price;

    return true;
  }

  function updateCollateralLTVRatio(address _address, uint256 _ltvRatio) public onlyOwner returns(bool) {

    require(collaterals[_address].isActive != false, "Collateral Not Available");

    collaterals[_address].ltvRatio = _ltvRatio;

    return true;
  }

  function getCollateralPrice(address _address) public view returns(uint256) {
    return collaterals[_address].price;
  }

}
