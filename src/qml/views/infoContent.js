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
    calc: "The node is asked how it is doing, and its own answer is what you "
        + "see — whether it considers itself caught up is its judgement, not a "
        + "guess made here. A momentary flicker is ignored: the node has to "
        + "report falling behind consistently before the headline changes, so "
        + "the card stays steady while it works. If it goes quiet, the last "
        + "known state stays on screen and greys out rather than being replaced "
        + "by something worse, because a node that is busy looks exactly like "
        + "one that is silent. Only when it stops answering entirely is it "
        + "reported as stopped.",
    states: [
        { label: "Not started",
          meaning: "The node is off, or was stopped. Nothing is running." },
        { label: "Starting",
          meaning: "Launching and checking configuration." },
        { label: "Bootstrapping",
          meaning: "Running, but still behind the head of the chain — either "
                 + "replaying blocks it already has, or fetching them from "
                 + "peers. The line underneath says which." },
        { label: "Online",
          meaning: "Running and caught up, following the chain." },
        { label: "Stopping",
          meaning: "Shutting down at your request." },
        { label: "Node stopped",
          meaning: "The node is no longer running, and it did not stop at "
                 + "your request. Nothing the dashboard last showed describes "
                 + "anything live. Start it again; if that reports the same "
                 + "thing, restart the app." },
        { label: "Disconnected",
          meaning: "The app lost contact with the node service it talks "
                 + "through — a different failure from the one above, and one "
                 + "it cannot repair on its own. Nothing on screen can be "
                 + "trusted while this shows. Restart the app." },
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
    calc: "Reported by the node once it comes online. Every running node "
        + "takes part at least as Edge; there is no setting that "
        + "turns blend off. Core is opted into: the node declares itself "
        + "through the Service Declaration Protocol, proving it holds a note "
        + "of at least the minimum stake, and the declaration only takes "
        + "effect two epochs later. A node that has just declared still "
        + "shows Edge until then — that is genuinely its role in the meantime, "
        + "not a stale reading.",
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
    calc: "Reported by the node while it is running. Peers and connections "
        + "are counted separately because one peer can hold more than one "
        + "connection, so the line beneath the figure reports the connections "
        + "those peers add up to. A node that is not running has neither, and "
        + "the counts are not kept from the last session. The peers it dials "
        + "on the way up come from the bootstrap list in its configuration.",
    states: [
        { label: "Count",
          meaning: "Connected peers, with total connections beneath." },
        { label: "0",
          meaning: "Running, but connected to nobody. This is the usual "
                 + "reason a node never finishes syncing: check that the "
                 + "bootstrap peers in its configuration are reachable and on "
                 + "the same network." },
        { label: "—",
          meaning: "The node is not running, or has not reported yet." }
    ],
    docs: "https://docs.logos.co/get-started/glossary"
}

// The prototype's sub-line for this tile is "Submitted: N", a count of claims
// in flight. The payload has no such field — it carries { tip, vouchers[],
// reward_amount, total_claimable } — so the line beneath reports the value of
// the vouchers instead, which is the unused half of what the node does send.
var readyToClaim = {
    title: "Ready to Claim",
    what: "Leader reward vouchers this wallet can claim right now. Every block "
        + "the node leads mints one; claiming redeems it into spendable "
        + "balance. The voucher is the receipt, not the money — the reward "
        + "itself lives on the ledger until it is claimed.",
    calc: "Only vouchers the wallet can currently prove are counted. Ones "
        + "already being claimed, or not yet provable, are left out — so this "
        + "can read lower than the number of blocks the node has led. The line "
        + "beneath is what they are worth: one voucher's payout right now, "
        + "multiplied by how many you hold. Treat it as an estimate rather "
        + "than a figure you are owed. The reward pool is shared across every "
        + "unclaimed voucher on the network, so it falls as other leaders "
        + "claim theirs, and the fee for the claim itself comes off the top — "
        + "expect to receive a little less than shown.",
    states: [
        { label: "Number",
          meaning: "Vouchers claimable now, with what they are worth beneath. "
                 + "Claim them from the Rewards tab." },
        { label: "0",
          meaning: "The wallet was asked and has nothing claimable — either "
                 + "nothing has been led yet, or it has all been claimed." },
        { label: "—",
          meaning: "Nothing reported yet — the node is off, or has not "
                 + "answered since the app started. Different from 0, which "
                 + "is an answer." }
    ],
    docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
}

var peerId = {
    title: "Peer ID",
    what: "This node's libp2p identity — the address other peers use to find "
        + "it and connect to it. It is the node's name on the network, not a "
        + "wallet or an account, and it holds no funds.",
    calc: "Derived from the node key in the selected user config, so it exists "
        + "before the node is ever started and does not change while it runs. "
        + "It belongs to the config rather than to the machine: point the app "
        + "at a different user config and this becomes a different node. The "
        + "tile shows the first 6 and last 4 characters to fit; the copy "
        + "button always takes the whole thing.",
    states: [
        { label: "12D3Ko…EwLz",
          meaning: "The shortened identity. Copy it to hand someone the full "
                 + "value — the shortened form is for reading, not for use." },
        { label: "—",
          meaning: "No user config is selected, or its node key could not be "
                 + "read. Nothing to do with the node being off: a valid "
                 + "config reports an ID whether or not anything is running." }
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
          meaning: "The staked value in LGO, grouped for reading." },
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

// The prototype's calc for this tile describes a different implementation: it
// reads the wall-clock head slot (current_slot from get_time_info), falls back
// to the tip's slot, and drives its sync check off the gap between the two.
// This app does none of that — see the comment on `d.synced` in
// NodeDashboardView.qml for why the slot-gap check was taken out.
var epoch = {
    title: "Epoch",
    what: "The consensus epoch the chain is in now. An epoch spans many slots, "
        + "and each new one refreshes the randomness and the eligible-stake set "
        + "used to elect block leaders — which is why stake takes effect on an "
        + "epoch boundary rather than the moment it arrives.",
    calc: "Reported by the node, which counts epochs from the chain's genesis. "
        + "The boundary between one epoch and the next is when the stake "
        + "snapshot and the leader-election randomness are both refreshed — so "
        + "a change in this number is the moment newly aged stake starts "
        + "counting toward winning slots.",
    states: [
        { label: "Number",
          meaning: "The current epoch, e.g. 174. Flashes when it advances." },
        { label: "—",
          meaning: "The node has not reported its time info yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#time-units"
}

var slot = {
    title: "Slot",
    what: "Cryptarchia divides time into fixed slots — about a second each on "
        + "the reference network — and every slot is one chance for a block to "
        + "be added. This is the slot the node's current tip sits in.",
    calc: "This is the slot of the node's most recent block, not the slot "
        + "the clock is in. On a quiet chain the two drift apart: between "
        + "blocks the number stands still while time keeps moving. That is "
        + "normal, and not a sign the node has fallen behind.",
    states: [
        { label: "Integer",
          meaning: "The tip's slot, e.g. 184502. Flashes when it advances, and is copyable from the line beneath." },
        { label: "—",
          meaning: "The node has not reported yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#time-units"
}

var height = {
    title: "Height",
    what: "How many blocks this node's chain holds, counting from genesis up "
        + "to its tip. Because it climbs as blocks are applied, it doubles as "
        + "the honest progress bar while the node is catching up: a height "
        + "that keeps rising is a node getting somewhere.",
    calc: "The number of blocks the node has applied, counted from genesis.",
    states: [
        { label: "Integer",
          meaning: "Block count, e.g. 92118. Flashes when it advances, and is copyable from the line beneath." },
        { label: "—",
          meaning: "The node has not reported yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia"
}

var lib = {
    title: "LiB — Last Immutable Block",
    what: "The most recent block that can no longer be undone. It is deep "
        + "enough that no competing fork can grow past it, so everything at or "
        + "below this point is settled — a payment confirmed here is final in "
        + "the way one at the tip is not yet.",
    calc: "A block becomes immutable once enough blocks have been built on "
        + "top of it; how many is set by the network's security parameter. "
        + "The tile shows that block's identifier shortened, and its copy "
        + "button carries the whole thing. The slot beneath is when the same "
        + "block was made, and copies separately. Some documentation calls "
        + "this the last irreversible block — the same thing under another "
        + "name.",
    states: [
        { label: "0x1a2b…9f0c",
          meaning: "The shortened header id, with its slot beneath. Each line "
                 + "copies its own value." },
        { label: "—",
          meaning: "The node has not reported yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#fork-choice-rule"
}

var tip = {
    title: "TiP — Tip",
    what: "The newest block this node has accepted — the head of the chain it "
        + "currently prefers. Everything between LiB and here is confirmed but "
        + "still reorganisable: a better fork could yet replace it, which is "
        + "exactly what makes LiB the line worth trusting.",
    calc: "The head of the branch the node currently prefers, chosen by the "
        + "fork-choice rule. A block identifier like LiB, shown shortened, "
        + "with the full value on the copy button.",
    states: [
        { label: "0x7d3e…b118",
          meaning: "The shortened header id of the current tip." },
        { label: "—",
          meaning: "The node has not reported yet." }
    ],
    docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#fork-choice-rule"
}
