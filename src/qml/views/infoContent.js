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
