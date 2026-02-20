.PHONY: setup build test

# Patch strict pragmas in v4 dependencies for compatibility with solc 0.8.34
setup:
	@echo "Patching v4 dependency pragmas for solc 0.8.34 compatibility..."
	@sed -i '' 's/pragma solidity 0\.8\.26;/pragma solidity >=0.8.26;/' \
		lib/v4-core/src/PoolManager.sol \
		lib/v4-periphery/src/PositionManager.sol \
		lib/v4-periphery/src/PositionDescriptor.sol \
		lib/v4-periphery/src/V4Router.sol \
		lib/v4-periphery/src/UniswapV4DeployerCompetition.sol \
		lib/v4-periphery/src/interfaces/IUniswapV4DeployerCompetition.sol \
		lib/v4-periphery/lib/v4-core/src/PoolManager.sol
	@echo "Done."

build: setup
	forge build

test: setup
	forge test
