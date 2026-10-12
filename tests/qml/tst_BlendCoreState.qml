import QtQuick
import QtTest

import Logos.BlockchainBackend 1.0

import "../../src/qml/dialogs"

// BlendCoreState on its own: every value the Blend Core dialog derives, from
// plain inputs. No backend, no node.
TestCase {
    id: testCase
    name: "BlendCoreState"

    Component {
        id: stateComponent
        BlendCoreState {}
    }

    // A state for a running, online node with the API, plus `props`.
    function make(props) {
        const base = { nodeRunning: true, nodeOnline: true, apiAvailable: true,
                       blendState: BlockchainBackend.BlendNotDeclared,
                       blendConfig: { port: 3400, zk_id: "zk", sdp_funding_pk: "sdp" },
                       requirements: { min_stake: "1000000000", minimum_network_size: 2 } }
        const s = createTemporaryObject(stateComponent, testCase, Object.assign(base, props || {}))
        verify(s, "BlendCoreState created")
        return s
    }

    // ---- stake note ----

    function test_stake_unread_is_unknown() {
        const s = make()
        compare(s.zkNotes, null)
        compare(s.stakeChecked, false)
        compare(s.stakeOk, null)
    }

    function test_stake_picks_the_smallest_qualifying_note() {
        const s = make({ zkNotes: [{ id: "big", value: "5000000000" },
                                   { id: "small", value: "999999999" },
                                   { id: "fit", value: "1200000000" },
                                   { id: "exact", value: "1000000000" }] })
        compare(s.stakeNoteId, "exact")
        compare(s.stakeNoteValue, "1000000000")
        compare(s.stakeOk, true)
    }

    function test_stake_skips_the_note_already_locked() {
        const s = make({ zkNotes: [{ id: "locked", value: "1000000000" },
                                   { id: "other", value: "3000000000" }],
                         blendStatus: { declaration: { locked_note_id: "locked" } } })
        compare(s.stakeNoteId, "other")
    }

    function test_stake_none_big_enough() {
        const s = make({ zkNotes: [{ id: "a", value: "800000000" }] })
        compare(s.stakeChecked, true)
        compare(s.stakeOk, false)
        compare(s.stakeNoteId, "")
    }

    function test_stake_compares_as_decimal_strings() {
        // Past 2^53 a Number loses digits; the pick must not.
        const s = make({ zkNotes: [{ id: "a", value: "18446744073709551615" },
                                   { id: "b", value: "18446744073709551614" }] })
        compare(s.stakeNoteId, "b")
    }

    // ---- SDP funding ----

    function test_fee_unknown_until_read() {
        compare(make().feeOk, null)
    }

    function test_fee_needs_one_activity_fee() {
        compare(make({ sdpFundingBalance: "1999" }).feeOk, false)
        compare(make({ sdpFundingBalance: "2000" }).feeOk, true)
    }

    // ---- public address ----

    function test_address_waits_for_peers_on_a_node_that_reports_it() {
        const s = make()
        compare(s.hostValue, "")
        compare(s.addressOk, null)
    }

    function test_address_missing_on_a_node_that_cannot_report_it() {
        const s = make({ apiAvailable: false })
        compare(s.addressOk, false)
        verify(s.addressProblem.indexOf("config file") >= 0)
    }

    function test_address_from_peers_builds_the_locator_on_the_blend_port() {
        const s = make({ reachability: { confirmed_external_addresses:
                                             ["/ip4/203.0.113.7/udp/3000/quic-v1"] } })
        compare(s.hostValue, "203.0.113.7")
        compare(s.locator, "/ip4/203.0.113.7/udp/3400/quic-v1")
        compare(s.fromConfig, false)
        compare(s.addressOk, true)
    }

    function test_address_falls_back_to_the_config() {
        const s = make({ blendConfig: { port: 41000,
                                        external_address: "/ip4/198.51.100.4/udp/3000/quic-v1" } })
        compare(s.fromConfig, true)
        compare(s.locator, "/ip4/198.51.100.4/udp/41000/quic-v1")
    }

    function test_address_prefers_what_peers_see_over_the_config() {
        const s = make({ blendConfig: { port: 3400,
                                        external_address: "/ip4/198.51.100.4/udp/3000/quic-v1" },
                         reachability: { confirmed_external_addresses:
                                             ["/ip4/203.0.113.7/udp/3000/quic-v1"] } })
        compare(s.hostValue, "203.0.113.7")
        compare(s.fromConfig, false)
    }

    function test_address_rejects_what_outsiders_cannot_reach() {
        const cases = [["192.168.1.20", "private"], ["10.0.0.3", "private"],
                       ["172.20.1.1", "private"], ["127.0.0.1", "private"],
                       ["100.72.0.9", "CGNAT"], ["300.1.1.1", "valid IPv4"]]
        for (const [ip, why] of cases) {
            const s = make({ apiAvailable: false,
                             blendConfig: { port: 3400, external_address: "/ip4/" + ip + "/udp/3000/quic-v1" } })
            compare(s.addressOk, false, ip)
            verify(s.addressProblem.indexOf(why) >= 0, ip + ": " + s.addressProblem)
        }
    }

    function test_address_needs_a_blend_port() {
        const s = make({ blendConfig: { external_address: "/ip4/203.0.113.7/udp/3000/quic-v1" } })
        compare(s.locator, "")
        compare(s.addressOk, false)
    }

    // ---- reachability and network ----

    function test_reachability_is_attested_without_the_api() {
        const s = make({ apiAvailable: false })
        compare(s.reachOk, false)
        s.attested = true
        compare(s.reachOk, true)
    }

    function test_reachability_follows_the_check() {
        compare(make({ reachability: {} }).reachOk, null)
        compare(make({ reachability: { reachable: null } }).reachOk, null)
        compare(make({ reachability: { reachable: false } }).reachOk, false)
        compare(make({ reachability: { reachable: true } }).reachOk, true)
    }

    function test_network_size() {
        compare(make().networkOk, null)
        compare(make({ blendStatus: { network_size: 1 } }).networkOk, false)
        compare(make({ blendStatus: { network_size: 2 } }).networkOk, true)
        compare(make({ apiAvailable: false, blendStatus: { network_size: 9 } }).networkOk, null)
    }

    // ---- all requirements ----

    function ready(props) {
        return make(Object.assign({
            zkNotes: [{ id: "n", value: "1000000000" }],
            sdpFundingBalance: "5000",
            reachability: { reachable: true,
                            confirmed_external_addresses: ["/ip4/203.0.113.7/udp/3000/quic-v1"] },
            blendStatus: { network_size: 3 } }, props || {}))
    }

    function test_all_met() {
        verify(ready().allMet)
    }

    function test_any_missing_requirement_blocks() {
        verify(!ready({ nodeOnline: false }).allMet)
        verify(!ready({ zkNotes: [] }).allMet)
        verify(!ready({ sdpFundingBalance: "0" }).allMet)
        verify(!ready({ reachability: { reachable: false,
                                        confirmed_external_addresses: ["/ip4/203.0.113.7/udp/3000/quic-v1"] } }).allMet)
        verify(!ready({ blendStatus: { network_size: 1 } }).allMet)
    }

    function test_unknown_network_size_blocks_only_where_it_can_be_known() {
        verify(!ready({ blendStatus: {} }).allMet)
        // Without the API: the address from the config, reachability attested.
        const s = ready({ apiAvailable: false, blendStatus: {},
                          blendConfig: { port: 3400, zk_id: "zk",
                                         external_address: "/ip4/203.0.113.7/udp/3000/quic-v1" } })
        s.attested = true
        verify(s.allMet)
    }

    function test_checks_idle_while_the_node_is_stopped() {
        const s = make({ nodeRunning: false, sdpFundingBalance: "5000" })
        compare(s.checked(s.feeOk), "idle")
        s.nodeRunning = true
        compare(s.checked(s.feeOk), true)
    }

    function test_bootstrapping_is_progress_not_failure() {
        compare(make({ nodeOnline: false }).onlineOk, null)
    }

    // ---- Blend state ----

    function test_state_flags() {
        const rows = [
            // state                               declared joining active inactive withdrawn canLeave step
            [BlockchainBackend.BlendUnknown,        false,   false,  false, false,   false,    false,   0],
            [BlockchainBackend.BlendNotDeclared,    false,   false,  false, false,   false,    false,   0],
            [BlockchainBackend.BlendPending,        true,    true,   false, false,   false,    false,   0],
            [BlockchainBackend.BlendActivating,     true,    true,   false, false,   false,    true,    1],
            [BlockchainBackend.BlendActive,         true,    false,  true,  false,   false,    true,    0],
            [BlockchainBackend.BlendInactive,       true,    false,  false, true,    false,    true,    0],
            [BlockchainBackend.BlendWithdrawn,      true,    false,  false, false,   true,     false,   0]]
        for (const r of rows) {
            const s = make({ blendState: r[0] })
            const tag = "state " + r[0]
            compare(s.declared, r[1], tag + " declared")
            compare(s.joining, r[2], tag + " joining")
            compare(s.active, r[3], tag + " active")
            compare(s.inactive, r[4], tag + " inactive")
            compare(s.withdrawn, r[5], tag + " withdrawn")
            compare(s.canLeave, r[6], tag + " canLeave")
            compare(s.step, r[7], tag + " step")
        }
    }

    function test_core_from_blend_info_without_the_api() {
        const s = make({ apiAvailable: false, coreFromRole: true,
                         blendState: BlockchainBackend.BlendUnknown })
        verify(s.active)
        verify(s.declared)
    }

    function test_heading_follows_the_stage() {
        compare(make().heading, "Enable Blend Core")
        const s = make()
        s.page = "confirm"
        compare(s.heading, "Confirm Blend Core")
        compare(make({ blendState: BlockchainBackend.BlendActivating }).heading, "Joining Blend Core")
        compare(make({ blendState: BlockchainBackend.BlendActive }).heading, "Blend Core")
        const leaving = make({ blendState: BlockchainBackend.BlendActive })
        leaving.confirmingLeave = true
        compare(leaving.heading, "Disable Blend Core")
        compare(make({ blendState: BlockchainBackend.BlendWithdrawn }).heading, "Leaving Blend Core")
    }

    function test_withdraw_epochs() {
        const s = make({ blendState: BlockchainBackend.BlendWithdrawn,
                         blendStatus: { declaration: { withdraw_at: 12 } } })
        compare(s.withdrawAt, 12)
        compare(make().withdrawAt, null)
        compare(make().unlockDelay, 3)
        compare(make({ requirements: { unlock_delay_epochs: 5 } }).unlockDelay, 5)
    }

    // ---- activation countdown ----

    function test_activation_eta() {
        // Epoch 8 of 150 one-second slots starts 1200 s after genesis.
        const s = make({ blendState: BlockchainBackend.BlendActivating,
                         blendStatus: { declaration: { active_from_epoch: 8 } },
                         requirements: { epoch_slots: 150 },
                         timeInfoJson: JSON.stringify({ slot_duration_ms: 1000,
                                                        genesis_time_unix_ms: 1000000 }) })
        s.now = 1000000 + 1200 * 1000 - 60 * 1000
        compare(s.activationEta, "~1 min")
        s.now = 1000000 + 1200 * 1000 - 5 * 3600 * 1000
        compare(s.activationEta, "~5h")
    }

    function test_activation_eta_needs_the_epoch_length() {
        const s = make({ blendStatus: { declaration: { active_from_epoch: 8 } },
                         timeInfoJson: JSON.stringify({ slot_duration_ms: 1000,
                                                        genesis_time_unix_ms: 0 }) })
        compare(s.activationEta, "")
    }

    // ---- reset ----

    function test_clear_reads() {
        const s = make({ zkNotes: [], sdpFundingBalance: "5", actionError: "x",
                         reachability: { reachable: true } })
        s.clearReads()
        compare(s.zkNotes, null)
        compare(s.sdpFundingBalance, "")
        compare(s.actionError, "")
        compare(s.reachOk, null)
    }
}
