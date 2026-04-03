# Tweet Threads

---

## Thread 1: Announcement

**1/**
hooked up ammplify to claude through MCP

you just talk to it and it LPs for you on monad lol. picks tick ranges, approves tokens, opens positions, collects fees

it actually works

**2/**
MCP is basically a way for AI to call functions. we just wrapped our contract calls as tools it can use

11 read tools (pool data, balances, positions, TVL) and 7 write tools (open/close positions, approvals, fee collection)

**3/**
the fun part is you don't have to think about ticks anymore

"open a position on WMON/USDC around current price" and it just... does it. figures out the range, checks allowances, approves, opens

been wanting this for a while tbh

**4/**
setup if you wanna try:

```
git clone ...
cd mcpserver && npm install
echo "AMMPLIFY_NETWORK=mainnet" > .env
npm run dev
```

one line in your claude config and you're good

don't even need a key to read data

**5/**
10 pools live on monad — WMON/USDC, USDC/WETH, WBTC/USDC, shMON/WMON, CHOG/WMON, etc

repo: github.com/itos-finance/AmmplifyPublic/tree/main/mcpserver

---

## Thread 2: How It Works

**1/**
for the nerds — how the ammplify MCP server works

**2/**
pulls data from two places:

our middleware (api.ammplify.xyz) for the indexed stuff — pool lists, positions, TVL, leaderboard

and straight on-chain via viem for real-time — slot0, balances, allowances, our diamond's getPoolInfo

**3/**
writes do simulate first then send

simulateContract catches reverts before you burn gas. matters more when an AI is picking what to call lol

everything goes through one diamond address (EIP-2535), viem routes by selector

**4/**
the thing that makes this work well is MCP resources — you give the AI docs about your protocol and it actually understands what it's doing instead of guessing

tools alone aren't enough, it needs context

**5/**
whole thing is like 700 lines of real code. most of it is just schema definitions

mainnet or testnet is one env var. auto-picks RPC, chain ID, addresses

github.com/itos-finance/AmmplifyPublic/tree/main/mcpserver

---

## Thread 3: The Walkthrough

**1/**
LP'd on ammplify through claude yesterday. no UI, just talking to it

kinda wild

**2/**
"what pools are on ammplify?"

it hits the middleware, comes back with 10 pools. WMON/USDC 0.3% has the most liquidity

**3/**
"show me WMON/USDC"

reads slot0, gets current price and tick. also calls our diamond for tree width. all live on-chain, not stale

**4/**
"approve and open a compounding position around current price"

it checks both allowances, sends the approves, calculates a tick range centered on current tick aligned to tickSpacing, opens the position

didn't touch a single input field

**5/**
"how's my position?" → shows balances and fees
"collect my fees" → done

you could have this run on a cron too. check positions daily, compound when it makes sense

**6/**
concentrated liquidity is a pain to use manually. but all the info to do it right is on-chain

turns out an AI with the right tools is pretty good at it

github.com/itos-finance/AmmplifyPublic/tree/main/mcpserver
