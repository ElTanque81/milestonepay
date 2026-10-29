<p align="center">
  <img src="assets/logo-wordmark.png" alt="MilestonePay" width="520" />
</p>

<p align="center">
  <b>Milestone-based freelancer escrow on Portaldot — paid in native POT.</b><br/>
  Portaldot Hacker House 2026 · Track: <b>Ecosystem DApps</b> · MIT
</p>

---

## The problem

Freelancers and clients who don't know each other have a trust problem:

- **Freelancers** fear doing the work and never getting paid.
- **Clients** fear paying up front and never getting the work.
- Platforms like Fiverr or Upwork solve this — but take 10–20 % in fees, hold funds for weeks and exclude many countries.

## The solution

**MilestonePay** is a trust-minimized escrow contract on **Portaldot Network V3.0**:

1. **Client** creates a project, splits it into milestones and locks the full budget in **POT**.
2. **Freelancer** accepts the job — from now on the client can't pull the money back.
3. For each milestone the freelancer **submits proof** (link / hash).
4. Client **approves → POT is paid out instantly**.
5. Client silent? After the **review period** the freelancer can **claim the payment himself**.
6. Disagreement? Client opens a **dispute** within the review period and a neutral **arbiter** decides.

No platform fee, no middleman holding funds — just a contract on Portaldot.

## How Portaldot is used

| Portaldot feature | Usage in MilestonePay |
|---|---|
| **EVM compatibility (V3.0)** | `MilestonePay.sol` is deployed on the Portaldot testnet |
| **Native POT** | Escrow, payouts and refunds are all in native POT (`msg.value`) — no wrapped token |
| **POT as gas** | Every action (create, accept, submit, approve, dispute, resolve) is a POT-paid transaction |

## Deployment (Portaldot testnet)

| | |
|---|---|
| Network | PortaldotV3 Testnet |
| EVM RPC | `https://test-evm-rpc-v3.portaldot.dev` |
| Chain ID | `420420777` |
| Token | `tPOTv3` |
| Contract | `0x10B3B2F22Cb94586d97f40000AAC89c66488a5ba` |
| Deploy tx | `0x55f7437882d526e509326a046205fcd8d51254905717eac82d9bbe1a625dc1fb` |
| Live dApp | https://milestonepay-portaldot.netlify.app |
| Deploy cost | ≈ 687 tPOTv3 (mostly the per-byte storage deposit for 8.6 KB of code) |
| Node explorer | https://node-console.portaldot.dev |

## Demo

🎬 Demo video: https://youtu.be/BFh4mn1Gpcw *(recorded on a local test chain — testnet video follows)*

Live frontend: https://milestonepay-portaldot.netlify.app

## Milestone lifecycle

```
            submit              approve
 Pending ───────────► Submitted ──────────► Released ✔
    │                    │   └── review period over → freelancer claims → Released ✔
    │                    │ dispute (needs arbiter)
    │                    ▼
    │                Disputed ──arbiter──► Released ✔ / Refunded ↩
    │
    └── client cancels (before accept) / freelancer withdraws ──► Refunded ↩
```

## Contract API

| Function | Who | What |
|---|---|---|
| `createProject(freelancer, arbiter, amounts[], reviewPeriod, title)` | client | creates and funds project (`msg.value` = sum of amounts) |
| `cancelProject(id)` | client | full refund, only before the freelancer accepted |
| `acceptProject(id)` | freelancer | accepts the job |
| `submitMilestone(id, i, proof)` | freelancer | submits proof of work |
| `approveMilestone(id, i)` | client | pays the milestone |
| `disputeMilestone(id, i)` | client | opens a dispute (within review period, arbiter required) |
| `claimAfterTimeout(id, i)` | freelancer | claims payment after the review period |
| `withdrawFromProject(id)` | freelancer | gives up the job, pending milestones are refunded |
| `resolveDispute(id, i, payFreelancer)` | arbiter | settles a dispute |
| `getProject`, `getMilestones`, `getProjectsOf`, `lockedAmount` | anyone | views |

Security: checks-effects-interactions, reentrancy guard, custom errors, max 20 milestones, review period 1 min – 30 days.

## Run it yourself

```bash
npm install
npm test                 # 19 unit tests (Hardhat)
cp .env.example .env     # RPC + chain ID are prefilled — add your TESTNET private key
npm run deploy           # deploys to Portaldot testnet, writes deployment.json
npm run abi              # copies the ABI into the frontend
```

Then put the contract address into `frontend/config.js` and open `frontend/index.html` (or serve the folder with any static host). Connect MetaMask — the app adds the Portaldot network automatically.

> Offline / restricted network? `npm run test:offline` compiles with the bundled solc-js instead of downloading the compiler.

### Funding the deployer (Portaldot specific)

On Portaldot the H160 (0x) address is mapped to a native SS58 address by the `revive` module. Before deploying:

1. Create a MetaMask account and add the PortaldotV3 Testnet (values above).
2. In the [node explorer](https://node-console.portaldot.dev) open **Developer → Runtime calls → reviveApi → accountId**, enter the 0x address and copy the returned `5…` address.
3. Send tPOTv3 from your native wallet to that `5…` address — the balance then shows up in MetaMask.

## Project structure

```
contracts/MilestonePay.sol   escrow contract
test/MilestonePay.test.js    19 Hardhat tests
scripts/deploy.js            deploy to Portaldot testnet
scripts/export-abi.js        ABI → frontend
frontend/                    single-page dApp (ethers v6, no build step)
assets/                      logo
```

## Roadmap

- AI-assisted dispute summary for the arbiter (compares milestone description with delivered proof)
- Arbiter pool with staking instead of a single arbiter
- Partial payouts / split decisions
- Reputation score per address based on completed milestones

## Development log

Built during Portaldot Hacker House 2026 (Oct 14 – Nov 6, 2026).

- 2026-10-28 — contract, tests, frontend, logo
- 2026-10-29 — deployed to PortaldotV3 Testnet via MetaMask (deploy.html), frontend live on Netlify
- 2026-11-0x — demo video & submission

## Credits

Open-source tools used: [Hardhat](https://hardhat.org) (MIT), [ethers.js v6](https://docs.ethers.org) (MIT), [Inter font](https://rsms.me/inter/) (OFL). Contract code is original.

## License

MIT — see [LICENSE](LICENSE).
