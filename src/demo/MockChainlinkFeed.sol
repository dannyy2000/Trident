// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal Chainlink AggregatorV3Interface-compatible mock for testnets.
///         Owner can push a new price at any time; the frontend Demo Controls panel calls setAnswer().
contract MockChainlinkFeed {
    address public immutable owner;
    uint8   public immutable decimals;

    int256  public latestAnswer;
    uint256 public updatedAt;
    uint80  private _roundId;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(int256 _initialAnswer, uint8 _decimals) {
        owner         = msg.sender;
        decimals      = _decimals;
        latestAnswer  = _initialAnswer;
        updatedAt     = block.timestamp;
        _roundId      = 1;
        emit AnswerUpdated(_initialAnswer, 1, block.timestamp);
    }

    function setAnswer(int256 _answer) external {
        require(msg.sender == owner, "only owner");
        _roundId++;
        latestAnswer = _answer;
        updatedAt    = block.timestamp;
        emit AnswerUpdated(_answer, _roundId, block.timestamp);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt_,
            uint80  answeredInRound
        )
    {
        return (_roundId, latestAnswer, updatedAt, updatedAt, _roundId);
    }

    function getRoundData(uint80 /* _roundId */)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, latestAnswer, updatedAt, updatedAt, _roundId);
    }

    function description() external pure returns (string memory) { return "Mock ETH/USD"; }
    function version()     external pure returns (uint256)        { return 3; }
}
