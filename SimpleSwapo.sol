 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract SimpleSwap {
    event LiquidityAdded(address indexed user, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    struct Pool {
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalLiquidity;
        mapping(address => uint256) liquidity;
    }

    mapping(address => mapping(address => Pool)) public pools;

    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction expired");
        _;
    }

    //  Agregar Liquidez
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(tokenA != tokenB, "Same tokens");
        require(amountADesired > 0 && amountBDesired > 0, "Zero amount");
        
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pool storage pool = pools[token0][token1];
        
        require(
            IERC20(tokenA).allowance(msg.sender, address(this)) >= amountADesired &&
            IERC20(tokenB).allowance(msg.sender, address(this)) >= amountBDesired,
            "Insufficient allowance"
        );

        if (pool.totalLiquidity == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            require(amountA >= amountAMin && amountB >= amountBMin, "Slippage too high");
            liquidity = sqrt(amountA * amountB);
        } else {
            (amountA, amountB) = calculateOptimalAmounts(
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                pool.reserve0,
                pool.reserve1
            );
            liquidity = (amountA * pool.totalLiquidity) / pool.reserve0;
        }

        transferTokens(tokenA, tokenB, amountA, amountB);
        updateReserves(pool, tokenA == token0, amountA, amountB);
        
        pool.totalLiquidity += liquidity;
        pool.liquidity[to] += liquidity;

        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }

    //  Remover Liquidez
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        require(tokenA != tokenB, "Same tokens");
        
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pool storage pool = pools[token0][token1];
        
        require(pool.liquidity[msg.sender] >= liquidity, "Insufficient liquidity");
        
        amountA = (liquidity * pool.reserve0) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserve1) / pool.totalLiquidity;
        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage too high");

        pool.reserve0 -= amountA;
        pool.reserve1 -= amountB;
        pool.totalLiquidity -= liquidity;
        pool.liquidity[msg.sender] -= liquidity;

        transferToUser(tokenA, tokenB, token0, to, amountA, amountB);

        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }

    //  Intercambiar Tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length == 2, "Only single swap supported");
        
        address tokenIn = path[0];
        address tokenOut = path[1];
        
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        
        Pool storage pool = getPool(tokenIn, tokenOut);
        (uint256 reserveIn, uint256 reserveOut) = getReserves(pool, tokenIn, tokenOut);
        
        amounts[1] = calculateAmountOut(amountIn, reserveIn, reserveOut);
        require(amounts[1] >= amountOutMin, "Insufficient output");

        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        _safeTransfer(tokenOut, to, amounts[1]);

        updateSwapReserves(pool, tokenIn < tokenOut, amountIn, amounts[1]);
        
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amounts[1]);
    }

    //  Obtener el Precio
    function getPrice(address tokenA, address tokenB) external view returns (uint256 price) {
        require(tokenA != tokenB, "Same tokens");
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pool storage pool = pools[token0][token1];
        require(pool.reserve0 > 0 && pool.reserve1 > 0, "No liquidity");
        price = tokenA == token0 ? 
            (pool.reserve1 * 1e18) / pool.reserve0 : 
            (pool.reserve0 * 1e18) / pool.reserve1;
    }

    //  Calcular Cantidad a Recibir
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "Insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997; // 0.3% fee
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    // Funciones auxiliares
    function sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function calculateOptimalAmounts(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 reserveA,
        uint256 reserveB
    ) private pure returns (uint256 amountA, uint256 amountB) {
        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "Insufficient B amount");
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
            require(amountAOptimal >= amountAMin, "Insufficient A amount");
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }

    function transferTokens(address tokenA, address tokenB, uint256 amountA, uint256 amountB) private {
        _safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        _safeTransferFrom(tokenB, msg.sender, address(this), amountB);
    }

    function updateReserves(Pool storage pool, bool isToken0, uint256 amountA, uint256 amountB) private {
        if (isToken0) {
            pool.reserve0 += amountA;
            pool.reserve1 += amountB;
        } else {
            pool.reserve0 += amountB;
            pool.reserve1 += amountA;
        }
    }

    function transferToUser(address tokenA, address tokenB, address token0, address to, uint256 amountA, uint256 amountB) private {
        if (tokenA == token0) {
            _safeTransfer(tokenA, to, amountA);
            _safeTransfer(tokenB, to, amountB);
        } else {
            _safeTransfer(tokenA, to, amountB);
            _safeTransfer(tokenB, to, amountA);
        }
    }

    function getPool(address tokenA, address tokenB) private view returns (Pool storage) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        return pools[token0][token1];
    }

    function getReserves(Pool storage pool, address tokenIn, address tokenOut) private view returns (uint256 reserveIn, uint256 reserveOut) {
        (reserveIn, reserveOut) = tokenIn < tokenOut ? (pool.reserve0, pool.reserve1) : (pool.reserve1, pool.reserve0);
    }

    function calculateAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        return (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997);
    }

    function updateSwapReserves(Pool storage pool, bool isToken0, uint256 amountIn, uint256 amountOut) private {
        if (isToken0) {
            pool.reserve0 += amountIn;
            pool.reserve1 -= amountOut;
        } else {
            pool.reserve1 += amountIn;
            pool.reserve0 -= amountOut;
        }
    }

    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
} 