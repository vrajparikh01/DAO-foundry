// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Timelock} from "../src/Timelock.sol";
import {GovToken} from "../src/GovToken.sol";
import {Box} from "../src/Box.sol";

contract GovernorTest is Test {
    MyGovernor public governor;
    Timelock public timelock;
    GovToken public govToken;
    Box public box;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hour after a vote is passed
    uint256 public constant VOTING_DELAY = 1; // 1 block delay before voting starts
    uint256 public constant VOTING_PERIOD = 50400; // 1 week voting period

    address[] public proposers;
    address[] public executors;

    bytes[] public calldatas;
    uint256[] public values;
    address[] public targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new Timelock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCannotUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(42);
    }

    function testGovernanceUpdatesBox() public {
        uint256 newValue = 100;
        string memory description = "Update box value to 100";
        bytes memory callData = abi.encodeWithSignature("store(uint256)", newValue);

        values.push(0);
        targets.push(address(box));
        calldatas.push(callData);

        // 1. Create a proposal
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        console.log("Proposal ID:", proposalId);
        console.log("Proposal State:", uint256(governor.state(proposalId))); // Should be in pending state

        vm.warp(block.timestamp + VOTING_DELAY + 1); // Move time forward to allow voting
        vm.roll(block.number + VOTING_DELAY + 1); // Move to the next block

        // Check proposal state
        console.log("Proposal State before voting:", uint256(governor.state(proposalId))); // Should be in Active state

        // 2. Vote on the proposal
        string memory reason = "I support this proposal";
        uint8 support = 1; // For the proposal

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, support, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1); // Move time forward to end voting period
        vm.roll(block.number + VOTING_PERIOD + 1); // Move to the next block

        // Check proposal state after voting
        console.log("Proposal State after voting:", uint256(governor.state(proposalId))); // Should be in Succeeded state

        // 3. Queue the proposal
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(
            targets,
            values,
            calldatas,
            descriptionHash
        );
        
        vm.warp(block.timestamp + MIN_DELAY + 1); // Move time forward to allow execution
        vm.roll(block.number + MIN_DELAY + 1); // Move to the next block

        // Check proposal state after queuing
        console.log("Proposal State after queuing:", uint256(governor.state(proposalId))); // Should be in Queued state

        // 4. Execute the proposal
        governor.execute(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        // Check the box value after execution
        uint256 boxValue = box.retrieve();
        console.log("Box value after execution:", boxValue);
        assertEq(boxValue, newValue, "Box value should be updated to 100");
    }
}