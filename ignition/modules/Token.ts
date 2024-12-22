// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MockERC20 = buildModule("MockERC20", (m) => {
    const mockERC20 = m.contract("MockERC20", [
        "MockERC20",
        "MOCK",
    ]);

    return { mockERC20 };
});

export default MockERC20;
