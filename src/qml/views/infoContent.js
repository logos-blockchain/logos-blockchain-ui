.pragma library

// Per-tile (i) content: { title, what, calc, states: [{label, meaning}], docs }.
// Shape and section order follow the dashboard prototype's infoContent.js.
//
// `calc` and `states` describe THIS implementation, not the prototype's. The
// prototype documents a slot-gap check and a ~60:00 bootstrapping countdown;
// neither exists here — the headline trusts the node's own `mode` — and its
// state list omits Stopping, Disconnected and Node stopped, all of which this
// hero renders. A dialog that explains states the user cannot see, and omits
// three they can, is worse than no dialog.

var status = {
    title: "Status",
    what: "The node's current lifecycle state — off, starting, catching up, or "
        + "fully online and following the chain. The dashboard's headline.",
    calc: "From the backend status enum (NotStarted / Starting / Running / "
        + "Stopping / Stopped / Error), combined with the node's own sync "
        + "verdict. 'Online' vs 'Bootstrapping' is not a slot-gap calculation: "
        + "the node reports mode Online once it is caught up, and the app "
        + "simply takes its word, debouncing a fall out of Online over three "
        + "consecutive readings so one blip cannot repaint the headline. "
        + "Losing the status poll never changes the state — the last known "
        + "headline stays and greys instead, because silence from a busy node "
        + "is a gap in our knowledge, not evidence about the node. What does "
        + "change it is asking the node module directly and getting no answer: "
        + "after three silent polls the app checks whether the module's process "
        + "is still there at all, and only then reports the node as stopped.",
    states: [
        { label: "Not started",
          meaning: "The node is off, or was stopped. Nothing is running." },
        { label: "Starting",
          meaning: "Launching and checking configuration." },
        { label: "Bootstrapping",
          meaning: "Running, but the chain is behind the head — replaying "
                 + "stored blocks or syncing from peers. The sub-line names "
                 + "which, because that is what differs if it stalls." },
        { label: "Online",
          meaning: "Running and caught up, following the chain." },
        { label: "Stopping",
          meaning: "Shutting down at your request." },
        { label: "Node stopped",
          meaning: "The node module's process is gone, so the node went with "
                 + "it. Whatever the dashboard last showed describes a node "
                 + "that no longer exists. Start it again; if that reports the "
                 + "same thing, restart the app to reload the module." },
        { label: "Disconnected",
          meaning: "This view lost contact with its own backend — a different "
                 + "failure from the one above, and one the app cannot repair "
                 + "from here. No state it showed can be trusted. Restart the "
                 + "app." },
        { label: "Error",
          meaning: "The node reported a failure; the message is shown beside "
                 + "the headline." }
    ],
    docs: "https://docs.logos.co/blockchain/get-started/run-a-logos-blockchain-node-from-basecamp"
}

// Like Peers below, the prototype lists this tile as unwired and shows a
// placeholder "Not active". blend_info is wired and is where Core/Edge comes
// from, so `calc` describes the real reading.
//
// `states` deliberately stops at the three the user can actually see. The view
// renders a fourth, "Not active", against BlendRole::Inactive — but no node
// reports it yet, and documenting a state nobody can reach is the mistake this
// file's header is about. Add it here when refreshBlendRole() can set it.
var blend = {
    title: "Blend",
    what: "Whether this node's block proposals travel through the Blend "
        + "Network — the mixnet that hides which node proposed a block. The "
        + "point is proposer privacy: without it the peer that announces a "
        + "block is the peer that made it, which is worth knowing to anyone "
        + "watching the network.",
    calc: "From the node's own blend_info, read once it comes online. Every "
        + "running node takes part at least as Edge; there is no setting that "
        + "turns blend off. Core is opted into: the node declares itself "
        + "through the Service Declaration Protocol, proving it holds a note "
        + "of at least the minimum stake, and the declaration only takes "
        + "effect two epochs later. A node that has just declared therefore "
        + "still reads Edge — that is its honest live role until the "
        + "declaration activates, not a stale reading.",
    states: [
        { label: "Edge",
          meaning: "The default for a running node. Its own proposals are "
                 + "mixed by the core network on their way out, but it does "
                 + "not mix anyone else's." },
        { label: "Core",
          meaning: "A declared blend node. It mixes traffic for others as well "
                 + "as itself, and earns rewards for doing so." },
        { label: "—",
          meaning: "The node is not running, or blend has not reported yet. "
                 + "The role is cleared rather than remembered, because a node "
                 + "that is off is mixing nothing." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-the-blend-network"
}

// The prototype lists this tile as unwired, needing a bridge to the node's HTTP
// API. It does not: get_network_info landed in the 0.3 module with the same
// counters, so this one is real.
var peers = {
    title: "Peers",
    what: "How many other nodes this node is connected to on the peer-to-peer "
        + "network. Peers are how it gossips blocks in and out — a node with "
        + "none can neither catch up nor publish anything it proposes.",
    calc: "The node's own libp2p connection counters, read on every status "
        + "poll while it is running. Peers and connections are counted "
        + "separately because one peer can hold more than one connection, so "
        + "the line beneath the figure reports the connections those peers add "
        + "up to. Only a running node has them: the counts are not remembered "
        + "across a stop, and the peers a node dials on the way up come from "
        + "the bootstrap list in its config.",
    states: [
        { label: "Count",
          meaning: "Connected peers, with total connections beneath." },
        { label: "0",
          meaning: "Running, but connected to nobody. This is the usual reason "
                 + "a node bootstraps forever: check that the bootstrap peers "
                 + "in its config are reachable and on the same network." },
        { label: "—",
          meaning: "The node is not running, or has not reported yet." }
    ],
    docs: "https://docs.logos.co/get-started/glossary"
}

// Checked against the node source rather than the docs site: stake is the aged
// note set the leader service plays the lottery with (the wallet service's
// get_leader_aged_notes), which is not the wallet balance.
var stake = {
    title: "Stake",
    what: "The value of this node's notes that are old enough to enter the "
        + "leadership lottery — the weight it plays with. Any note counts; "
        + "Cryptarchia sets no minimum stake.",
    calc: "The node reports the notes it can lead with, and this is their "
        + "total value. A note counts once it is in the epoch's stake "
        + "snapshot, which is taken at the start of the epoch — so tokens that "
        + "arrive after a snapshot wait for the next one, up to two epochs, "
        + "before they add to stake. That is why this can read lower than the "
        + "wallet balance, and why a freshly funded node stakes nothing for a "
        + "while. Each claimed leader reward arrives as its own note and ages "
        + "on its own clock, so the stake climbs in steps at epoch boundaries "
        + "rather than at the moment a reward is claimed. The lottery counts "
        + "notes on ANY key the keystore holds, not one designated key. Today "
        + "that is a single key — rewards are minted to the same leader "
        + "funding key the notes already sit on — so the address is shown "
        + "beneath the figure. Leader keys are expected to rotate, and once "
        + "notes span several keys no single address describes the stake: the "
        + "line beneath then reports how many notes and keys it is spread "
        + "across instead.",
    states: [
        { label: "Amount",
          meaning: "The staked value in LGO, grouped for reading. The node "
                 + "reports a plain count of base units (1 LOGOS = 10^9 "
                 + "lepta) and publishes no denomination of its own, so the "
                 + "9-decimal scale is the app's, not the chain's." },
        { label: "Address · N notes",
          meaning: "Beneath the figure while all the staked notes sit on one "
                 + "key: the address holding them, copyable in full, and how "
                 + "many notes make up the total. The address is where the "
                 + "stake is, not a permanent account identity — expect it to "
                 + "change as keys rotate." },
        { label: "N notes · M keys",
          meaning: "The address drops off once the notes span more than one "
                 + "key, because no single one of them describes the stake." },
        { label: "0",
          meaning: "Nothing has aged in. The wallet may well hold tokens — "
                 + "they just are not in an epoch snapshot yet, so the node "
                 + "cannot win a slot with them." },
        { label: "—",
          meaning: "The node is not running, or has not reported yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#leadership-election"
}
