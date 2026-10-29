// PortaldotV3 testnet (source: official PortaldotV3 Testnet Guide, endpoints as of Oct 16, 2026)
window.MILESTONEPAY_CONFIG = {
  contractAddress: "0x10B3B2F22Cb94586d97f40000AAC89c66488a5ba", // deployed Oct 29, 2026
  chainId: 420420777,
  chainName: "PortaldotV3 Testnet",
  rpcUrl: "https://test-evm-rpc-v3.portaldot.dev",
  explorerUrl: "",                  // no EVM block explorer yet
  // Native tPOTv3 has 14 decimals on the Substrate side; the EVM RPC (revive)
  // exposes balances with the usual 18 decimals, so 18 is correct here.
  currency: { name: "Portaldot Testnet", symbol: "tPOTv3", decimals: 18 },
};
