# SimpleSwap

Un contrato inteligente de intercambio de tokens ERC-20 y gestión de liquidez.

## Funcionalidades Principales

### 1. Agregar Liquidez
Permite a los usuarios aportar dos tokens a un pool y recibir tokens de liquidez a cambio.

```solidity
function addLiquidity(
  address tokenA,
  address tokenB,
  uint amountADesired,
  uint amountBDesired,
  uint amountAMin,
  uint amountBMin,
  address to,
  uint deadline
) external returns (uint amountA, uint amountB, uint liquidity);
```

### 2. Remover Liquidez
Permite a los usuarios retirar su liquidez de un pool, recibiendo de vuelta los tokens aportados.

```solidity
function removeLiquidity(
  address tokenA,
  address tokenB,
  uint liquidity,
  uint amountAMin,
  uint amountBMin,
  address to,
  uint deadline
) external returns (uint amountA, uint amountB);
```

### 3. Intercambiar Tokens
Intercambia una cantidad exacta de un token por otro según las reservas del pool.

```solidity
function swapExactTokensForTokens(
  uint amountIn,
  uint amountOutMin,
  address[] calldata path,
  address to,
  uint deadline
) external returns (uint[] memory amounts);
```

### 4. Obtener el Precio
Devuelve el precio actual de un token respecto a otro, basado en las reservas del pool.

```solidity
function getPrice(address tokenA, address tokenB) external view returns (uint price);
```

### 5. Calcular Cantidad de Salida
Calcula cuántos tokens se recibirán al intercambiar una cantidad determinada.

```solidity
function getAmountOut(
  uint amountIn,
  uint reserveIn,
  uint reserveOut
) external pure returns (uint amountOut);
```

## Requisitos
- Solidity ^0.8.20
- Tokens ERC-20 compatibles

## Licencia
MIT

