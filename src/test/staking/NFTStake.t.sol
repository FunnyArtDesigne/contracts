// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { NFTStake } from "contracts/staking/NFTStake.sol";

// Test imports
import "contracts/lib/TWStrings.sol";
import "../utils/BaseTest.sol";

contract NFTStakeTest is BaseTest {
    NFTStake internal stakeContract;

    address internal stakerOne;
    address internal stakerTwo;

    uint256 internal timeUnit;
    uint256 internal rewardsPerUnitTime;

    function setUp() public override {
        super.setUp();

        timeUnit = 60;
        rewardsPerUnitTime = 1;

        stakerOne = address(0x345);
        stakerTwo = address(0x567);

        erc721.mint(stakerOne, 5); // mint token id 0 to 4
        erc721.mint(stakerTwo, 5); // mint token id 5 to 9
        erc20.mint(deployer, 1000 ether); // mint reward tokens to contract admin

        stakeContract = NFTStake(getContract("NFTStake"));

        // set approvals
        vm.prank(stakerOne);
        erc721.setApprovalForAll(address(stakeContract), true);

        vm.prank(stakerTwo);
        erc721.setApprovalForAll(address(stakeContract), true);

        vm.prank(deployer);
        erc20.transfer(address(stakeContract), 100 ether);
    }

    /*///////////////////////////////////////////////////////////////
                            Unit tests: Stake
    //////////////////////////////////////////////////////////////*/

    function test_state_stake() public {
        //================ first staker ======================
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);
        uint256 timeOfLastUpdate_one = block.timestamp;

        // check balances/ownership of staked tokens
        for (uint256 i = 0; i < _tokenIdsOne.length; i++) {
            assertEq(erc721.ownerOf(_tokenIdsOne[i]), address(stakeContract));
            assertEq(stakeContract.stakerAddress(_tokenIdsOne[i]), stakerOne);
        }
        assertEq(erc721.balanceOf(stakerOne), 2);
        assertEq(erc721.balanceOf(address(stakeContract)), _tokenIdsOne.length);

        // check available rewards right after staking
        (uint256[] memory _amountStaked, uint256 _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(_amountStaked.length, _tokenIdsOne.length);
        assertEq(_availableRewards, 0);

        //=================== warp timestamp to calculate rewards
        vm.roll(100);
        vm.warp(1000);

        // check available rewards after warp
        (, _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _availableRewards,
            ((((block.timestamp - timeOfLastUpdate_one) * _tokenIdsOne.length) * rewardsPerUnitTime) / timeUnit)
        );

        //================ second staker ======================
        vm.roll(200);
        vm.warp(2000);
        uint256[] memory _tokenIdsTwo = new uint256[](2);
        _tokenIdsTwo[0] = 5;
        _tokenIdsTwo[1] = 6;

        // stake 2 tokens
        vm.prank(stakerTwo);
        stakeContract.stake(_tokenIdsTwo);
        uint256 timeOfLastUpdate_two = block.timestamp;

        // check balances/ownership of staked tokens
        for (uint256 i = 0; i < _tokenIdsTwo.length; i++) {
            assertEq(erc721.ownerOf(_tokenIdsTwo[i]), address(stakeContract));
            assertEq(stakeContract.stakerAddress(_tokenIdsTwo[i]), stakerTwo);
        }
        assertEq(erc721.balanceOf(stakerTwo), 3);
        assertEq(erc721.balanceOf(address(stakeContract)), _tokenIdsTwo.length + _tokenIdsOne.length);

        // check available rewards right after staking
        (_amountStaked, _availableRewards) = stakeContract.getStakeInfo(stakerTwo);

        assertEq(_amountStaked.length, _tokenIdsTwo.length);
        assertEq(_availableRewards, 0);

        //=================== warp timestamp to calculate rewards
        vm.roll(300);
        vm.warp(3000);

        // check available rewards for stakerOne
        (, _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _availableRewards,
            ((((block.timestamp - timeOfLastUpdate_one) * _tokenIdsOne.length) * rewardsPerUnitTime) / timeUnit)
        );

        // check available rewards for stakerTwo
        (, _availableRewards) = stakeContract.getStakeInfo(stakerTwo);

        assertEq(
            _availableRewards,
            ((((block.timestamp - timeOfLastUpdate_two) * _tokenIdsTwo.length) * rewardsPerUnitTime) / timeUnit)
        );
    }

    function test_revert_stake_stakingZeroTokens() public {
        // stake 0 tokens
        uint256[] memory _tokenIds;

        vm.prank(stakerOne);
        vm.expectRevert("Staking 0 tokens");
        stakeContract.stake(_tokenIds);
    }

    function test_revert_stake_notStaker() public {
        // stake unowned tokens
        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = 6;

        vm.prank(stakerOne);
        vm.expectRevert("Not owned or approved");
        stakeContract.stake(_tokenIds);
    }

    /*///////////////////////////////////////////////////////////////
                            Unit tests: claimRewards
    //////////////////////////////////////////////////////////////*/

    function test_state_claimRewards() public {
        //================ first staker ======================
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);
        uint256 timeOfLastUpdate_one = block.timestamp;

        //=================== warp timestamp to claim rewards
        vm.roll(100);
        vm.warp(1000);

        vm.prank(stakerOne);
        stakeContract.claimRewards();

        // check reward balances
        assertEq(
            erc20.balanceOf(stakerOne),
            ((((block.timestamp - timeOfLastUpdate_one) * _tokenIdsOne.length) * rewardsPerUnitTime) / timeUnit)
        );

        // check available rewards after claiming
        (uint256[] memory _amountStaked, uint256 _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(_amountStaked.length, _tokenIdsOne.length);
        assertEq(_availableRewards, 0);
    }

    function test_revert_claimRewards_noRewards() public {
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);

        //=================== try to claim rewards in same block

        vm.prank(stakerOne);
        vm.expectRevert("No rewards");
        stakeContract.claimRewards();

        //======= withdraw tokens and claim rewards
        vm.roll(100);
        vm.warp(1000);

        vm.prank(stakerOne);
        stakeContract.withdraw(_tokenIdsOne);
        vm.prank(stakerOne);
        stakeContract.claimRewards();

        //===== try to claim rewards again
        vm.roll(200);
        vm.warp(2000);
        vm.prank(stakerOne);
        vm.expectRevert("No rewards");
        stakeContract.claimRewards();
    }

    /*///////////////////////////////////////////////////////////////
                        Unit tests: stake conditions
    //////////////////////////////////////////////////////////////*/

    function test_state_setRewardsPerUnitTime() public {
        // check current value
        assertEq(rewardsPerUnitTime, stakeContract.rewardsPerUnitTime());

        // set new value and check
        uint256 newRewardsPerUnitTime = 50;
        vm.prank(deployer);
        stakeContract.setRewardsPerUnitTime(newRewardsPerUnitTime);
        assertEq(newRewardsPerUnitTime, stakeContract.rewardsPerUnitTime());

        //================ stake tokens
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);
        uint256 timeOfLastUpdate = block.timestamp;

        //=================== warp timestamp and again set rewardsPerUnitTime
        vm.roll(100);
        vm.warp(1000);

        vm.prank(deployer);
        stakeContract.setRewardsPerUnitTime(200);
        assertEq(200, stakeContract.rewardsPerUnitTime());
        uint256 newTimeOfLastUpdate = block.timestamp;

        // check available rewards -- should use previous value for rewardsPerUnitTime for calculation
        (, uint256 _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _availableRewards,
            ((((block.timestamp - timeOfLastUpdate) * _tokenIdsOne.length) * newRewardsPerUnitTime) / timeUnit)
        );

        //====== check rewards after some time
        vm.roll(300);
        vm.warp(3000);

        (, uint256 _newRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _newRewards,
            _availableRewards + ((((block.timestamp - newTimeOfLastUpdate) * _tokenIdsOne.length) * 200) / timeUnit)
        );
    }

    function test_revert_setRewardsPerUnitTime_notAuthorized() public {
        vm.expectRevert("Not authorized");
        stakeContract.setRewardsPerUnitTime(1);
    }

    function test_state_setTimeUnit() public {
        // check current value
        assertEq(timeUnit, stakeContract.timeUnit());

        // set new value and check
        uint256 newTimeUnit = 1 minutes;
        vm.prank(deployer);
        stakeContract.setTimeUnit(newTimeUnit);
        assertEq(newTimeUnit, stakeContract.timeUnit());

        //================ stake tokens
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);
        uint256 timeOfLastUpdate = block.timestamp;

        //=================== warp timestamp and again set rewardsPerUnitTime
        vm.roll(100);
        vm.warp(1000);

        vm.prank(deployer);
        stakeContract.setTimeUnit(1 seconds);
        assertEq(1 seconds, stakeContract.timeUnit());
        uint256 newTimeOfLastUpdate = block.timestamp;

        // check available rewards -- should use previous value for rewardsPerUnitTime for calculation
        (, uint256 _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _availableRewards,
            ((((block.timestamp - timeOfLastUpdate) * _tokenIdsOne.length) * rewardsPerUnitTime) / newTimeUnit)
        );

        //====== check rewards after some time
        vm.roll(300);
        vm.warp(3000);

        (, uint256 _newRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _newRewards,
            _availableRewards +
                ((((block.timestamp - newTimeOfLastUpdate) * _tokenIdsOne.length) * rewardsPerUnitTime) / (1 seconds))
        );
    }

    function test_revert_setTimeUnit_notAuthorized() public {
        vm.expectRevert("Not authorized");
        stakeContract.setTimeUnit(1);
    }

    /*///////////////////////////////////////////////////////////////
                            Unit tests: withdraw
    //////////////////////////////////////////////////////////////*/

    function test_state_withdraw() public {
        //================ first staker ======================
        vm.warp(1);
        uint256[] memory _tokenIdsOne = new uint256[](3);
        _tokenIdsOne[0] = 0;
        _tokenIdsOne[1] = 1;
        _tokenIdsOne[2] = 2;

        // stake 3 tokens
        vm.prank(stakerOne);
        stakeContract.stake(_tokenIdsOne);
        uint256 timeOfLastUpdate = block.timestamp;

        // check balances/ownership of staked tokens
        for (uint256 i = 0; i < _tokenIdsOne.length; i++) {
            assertEq(erc721.ownerOf(_tokenIdsOne[i]), address(stakeContract));
            assertEq(stakeContract.stakerAddress(_tokenIdsOne[i]), stakerOne);
        }
        assertEq(erc721.balanceOf(stakerOne), 2);
        assertEq(erc721.balanceOf(address(stakeContract)), _tokenIdsOne.length);

        // check available rewards right after staking
        (uint256[] memory _amountStaked, uint256 _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(_amountStaked.length, _tokenIdsOne.length);
        assertEq(_availableRewards, 0);

        console.log("==== staked tokens before withdraw ====");
        for (uint256 i = 0; i < _amountStaked.length; i++) {
            console.log(_amountStaked[i]);
        }

        //========== warp timestamp before withdraw
        vm.roll(100);
        vm.warp(1000);

        uint256[] memory _tokensToWithdraw = new uint256[](1);
        _tokensToWithdraw[0] = 1;

        vm.prank(stakerOne);
        stakeContract.withdraw(_tokensToWithdraw);

        // check balances/ownership after withdraw
        for (uint256 i = 0; i < _tokensToWithdraw.length; i++) {
            assertEq(erc721.ownerOf(_tokensToWithdraw[i]), stakerOne);
            assertEq(stakeContract.stakerAddress(_tokensToWithdraw[i]), address(0));
        }
        assertEq(erc721.balanceOf(stakerOne), 3);
        assertEq(erc721.balanceOf(address(stakeContract)), 2);

        // check available rewards after withdraw
        (_amountStaked, _availableRewards) = stakeContract.getStakeInfo(stakerOne);
        assertEq(_availableRewards, ((((block.timestamp - timeOfLastUpdate) * 3) * rewardsPerUnitTime) / timeUnit));

        console.log("==== staked tokens after withdraw ====");
        for (uint256 i = 0; i < _amountStaked.length; i++) {
            console.log(_amountStaked[i]);
        }

        uint256 timeOfLastUpdateLatest = block.timestamp;

        // check available rewards some time after withdraw
        vm.roll(200);
        vm.warp(2000);

        (, _availableRewards) = stakeContract.getStakeInfo(stakerOne);

        assertEq(
            _availableRewards,
            (((((timeOfLastUpdateLatest - timeOfLastUpdate) * 3)) * rewardsPerUnitTime) / timeUnit) +
                (((((block.timestamp - timeOfLastUpdateLatest) * 2)) * rewardsPerUnitTime) / timeUnit)
        );

        // stake again
        vm.prank(stakerOne);
        stakeContract.stake(_tokensToWithdraw);

        _tokensToWithdraw[0] = 5;
        vm.prank(stakerTwo);
        stakeContract.stake(_tokensToWithdraw);
        // check available rewards after re-staking
        (_amountStaked, ) = stakeContract.getStakeInfo(stakerOne);

        console.log("==== staked tokens after re-staking ====");
        for (uint256 i = 0; i < _amountStaked.length; i++) {
            console.log(_amountStaked[i]);
        }
    }

    function test_revert_withdraw_withdrawingZeroTokens() public {
        uint256[] memory _tokensToWithdraw;

        vm.expectRevert("Withdrawing 0 tokens");
        stakeContract.withdraw(_tokensToWithdraw);
    }

    function test_revert_withdraw_notStaker() public {
        // stake tokens
        uint256[] memory _tokenIds = new uint256[](2);
        _tokenIds[0] = 0;
        _tokenIds[1] = 1;

        vm.prank(stakerOne);
        stakeContract.stake(_tokenIds);

        // trying to withdraw zero tokens
        uint256[] memory _tokensToWithdraw = new uint256[](1);
        _tokensToWithdraw[0] = 2;

        vm.prank(stakerOne);
        vm.expectRevert("Not staker");
        stakeContract.withdraw(_tokensToWithdraw);
    }

    function test_revert_withdraw_withdrawingMoreThanStaked() public {
        // stake tokens
        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = 0;

        vm.prank(stakerOne);
        stakeContract.stake(_tokenIds);

        // trying to withdraw tokens not staked by caller
        uint256[] memory _tokensToWithdraw = new uint256[](2);
        _tokensToWithdraw[0] = 0;
        _tokensToWithdraw[1] = 1;

        vm.prank(stakerOne);
        vm.expectRevert("Withdrawing more than staked");
        stakeContract.withdraw(_tokensToWithdraw);
    }
}
