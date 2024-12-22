// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const YieldFarm = buildModule("YieldFarm", (m) => {
    const rewardRate = m.getParameter("rewardRate", 5);
    const lpToken = m.getParameter("lpToken");
    const rewardToken = m.getParameter("rewardToken");

    const yieldFarm = m.contract("YieldFarm", [
        lpToken,
        rewardToken,
        rewardRate,
    ]);

    return { yieldFarm };
});

export default YieldFarm;
