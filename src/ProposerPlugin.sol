// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

import { PluginUUPSUpgradeable, IDAO } from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import { ProposalUpgradeable } from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
/**
 * @title ProposerPlugin
 * @author Aragon (engineering@aragon.org)
 * @notice A plugin for Aragon OSx which allows allowlisted addresses
 * to propose transactions with a delay before execution.
 */

contract ProposerPlugin is PluginUUPSUpgradeable {
    /// @notice The ID of the permission required to propose a transaction.
    bytes32 public constant PROPOSER_ROLE_ID = keccak256("PROPOSER_ROLE");

    /// @notice The ID of the permission required to execute a transaction immediately.
    bytes32 public constant FAST_EXECUTE_ROLE_ID = keccak256("FAST_EXECUTE_ROLE");

    /// @notice The ID of the permission required to configure the plugin.
    bytes32 public constant CONFIG_ROLE_ID = keccak256("CONFIG_ROLE");

    /// @notice The delay before a proposed transaction can be executed.
    uint256 public delay;

    /// @notice The maximum delay that can be set for a proposed transaction.
    /// @dev This is set to 4 weeks.
    uint256 public constant maxDelay = 4 weeks;

    /// @notice Struct to store execution requests.
    struct ExecutionRequests {
        IDAO.Action[] actions; // The actions to be executed.
        uint256 timestamp; // The timestamp when the transaction was proposed.
        bool executed; // Flag to check if the transaction has been executed or not.
        uint256 allowFailureMap; // A bitmap allowing the proposal to succeed, even if individual actions might revert.
            // If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value
            // of 0 requires every action to not revert.
    }

    /// @notice The ID for the next execution request.
    uint256 nextExecutionRequestId;

    /// @notice A mapping from execution request ID to the execution request details.
    mapping(uint256 => ExecutionRequests) internal executionRequests;

    function initialize(IDAO _dao, uint256 _delay) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
        delay = _delay;
        nextExecutionRequestId = 0;
    }

    // ------------------------------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------------------------------

    /// @notice Emitted when a new execution request is created.
    /// @param executionRequestId The unique identifier of the proposed transaction.
    /// @param metadata The metadata of the proposal.
    /// @param actions The actions to be executed.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    event ExecutionCreated(
        uint256 indexed executionRequestId, bytes metadata, IDAO.Action[] actions, uint256 allowFailureMap
    );

    /// @notice Emitted when the delay is changed.
    /// @param delay The new delay in seconds.
    event DelayChanged(uint256 delay);

    /// @notice Emitted when a transaction is executed.
    /// @param executionRequestId The unique identifier of the proposed transaction.
    event ExecutionExecuted(uint256 indexed executionRequestId);

    // ------------------------------------------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------------------------------------------

    error AlreadyExecuted(uint256 executionRequestId);

    // ------------------------------------------------------------------------------------------------------------
    // Unpermissioned functions
    // ------------------------------------------------------------------------------------------------------------

    /// @notice Allows a allowlisted proposer to propose a transaction.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions to be executed.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If
    /// the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0
    /// requires every action to not revert.
    function createExecution(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap
    )
        external
        auth(PROPOSER_ROLE_ID)
        returns (uint256 executionRequestId)
    {
        executionRequestId = nextExecutionRequestId++;
        ExecutionRequests storage executionRequest = executionRequests[executionRequestId];
        // executionRequest.actions = _actions;
        executionRequest.timestamp = block.timestamp;
        executionRequest.executed = false;

        // Reduce costs
        if (_allowFailureMap != 0) {
            executionRequest.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length;) {
            executionRequest.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        emit ExecutionCreated(executionRequestId, _metadata, _actions, _allowFailureMap);
        return executionRequestId;
    }

    /// @notice Allows anyone to execute a transaction after its delay.
    /// @param executionRequestId The unique identifier of the proposed transaction.
    function executeExecution(uint256 executionRequestId) external {
        ExecutionRequests storage executionRequest = executionRequests[executionRequestId];
        if (executionRequest.executed == true) revert AlreadyExecuted(executionRequestId);
        executionRequest.executed = true;

        _executeFromDao(executionRequestId);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Permissioned functions
    // ------------------------------------------------------------------------------------------------------------

    /// @notice Allows an approved proposer to execute a transaction immediately, bypassing the delay.
    /// @param executionRequestId The unique identifier of the proposed transaction.
    function executeExecutionFast(uint256 executionRequestId) external auth(FAST_EXECUTE_ROLE_ID) {
        _executeFromDao(executionRequestId);
    }

    /// @notice Allows the address with CONFIG_ROLE to change the delay period.
    /// @param _delay The new delay in seconds.
    function changeDelay(uint256 _delay) external auth(CONFIG_ROLE_ID) {
        delay = _delay;
        emit DelayChanged(_delay);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------------------------------------

    /// @notice Internal function for executing transactions from DAO.
    function _executeFromDao(uint256 executionRequestId)
        internal
        returns (bytes[] memory execResults, uint256 failureMap)
    {
        ExecutionRequests storage executionRequest = executionRequests[executionRequestId];

        (execResults, failureMap) = dao().execute({
            _callId: bytes32(executionRequestId),
            _actions: executionRequest.actions,
            _allowFailureMap: executionRequest.allowFailureMap
        });
        emit ExecutionExecuted(executionRequestId);
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables without shifting
    /// down storage in the inheritance chain (see [OpenZepplins guide about storage
    /// gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[49] private __gap;
}
