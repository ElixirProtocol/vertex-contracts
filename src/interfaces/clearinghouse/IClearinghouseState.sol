// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../engine/IProductEngine.sol";
import "../IEndpoint.sol";

interface IClearinghouseState {
    struct RiskStore {
        // these weights are all
        // between 0 and 2
        // these integers are the real
        // weights times 1e9
        int32 longWeightInitial;
        int32 shortWeightInitial;
        int32 longWeightMaintenance;
        int32 shortWeightMaintenance;
        int32 largePositionPenalty;
    }

    struct HealthGroup {
        uint32 spotId;
        uint32 perpId;
    }

    function getMaxHealthGroup() external view returns (uint32);
}
