// The referral signing intents' formats and signatures, against values computed by
// uplink_module's own code (logos-blockchain/uplink-module, domain::enrolment and
// domain::cashout), so what this app signs is what the module checks.

#include <logos_test.h>

#include <QCryptographicHash>

#include "ReferralSigning.h"

using namespace referral_signing;

namespace {

const QByteArray kSeed = QByteArray(32, '\x01');
const QString kNode = QStringLiteral("8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c");
const QString kProgram = QStringLiteral("0909090909090909090909090909090909090909090909090909090909090909");
const QString kParticipant = QStringLiteral("0303030303030303030303030303030303030303030303030303030303030303");
const QString kReferrer = QStringLiteral("0505050505050505050505050505050505050505050505050505050505050505");
const QString kBlinding = QStringLiteral("0404040404040404040404040404040404040404040404040404040404040404");

// A keystore as node 0.3.1 writes one, with other keys around the BlendSigning ones.
QByteArray keystore(const QString& publicKey = kNode, const QByteArray& secret = kSeed)
{
    return "public_keys:\n"
           "  BlendSigning: " + publicKey.toLatin1() + "\n"
           "  NetworkSwarm: " + QByteArray(64, 'b') + "\n"
           "secret_keys:\n"
           "  BlendZk: !Zk " + QByteArray(64, 'c') + "\n"
           "  BlendSigning: !Ed25519 " + secret.toHex() + "\n"
           "  NetworkSwarm: !Ed25519 " + QByteArray(64, 'd') + "\n"
           "WARNING: Do not share your secret keys\n";
}

Answer run(const QString& intent, const QVariantMap& params, const QByteArray& yaml = keystore())
{
    Prepared prepared;
    QString error;
    if (!prepare(intent, params, yaml, prepared, error))
        return {false, {}, error};
    return answer(prepared, yaml);
}

} // namespace

LOGOS_TEST(the_enrolment_message_is_the_programs) {
    // uplink's own vector (programs/referral/core: the_authorization_message_is_...).
    const QByteArray message = enrolmentMessage(QByteArray(32, '\x09'), QByteArray(32, '\x07'), QByteArray(32, '\x03'), {});
    LOGOS_ASSERT_EQ(message.size(), 128);
    LOGOS_ASSERT_EQ(QString::fromLatin1(QCryptographicHash::hash(message, QCryptographicHash::Sha256).toHex()),
                    QString("88b3189599fb9244334344a9b8581e1f7e8f85bbb77935d0ebe548aabab27ee7"));
    LOGOS_ASSERT_EQ(enrolmentMessage(QByteArray(32, '\x09'), QByteArray(32, '\x07'), QByteArray(32, '\x03'),
                                     QByteArray(32, '\x05')).size(), 160);
}

LOGOS_TEST(the_node_signs_the_enrolment_uplink_module_checks) {
    const Answer alone = run(kEnrolIntent, {{"program", kProgram}, {"participant_account", kParticipant}, {"referrer", ""}});
    LOGOS_ASSERT_TRUE(alone.ok);
    LOGOS_ASSERT_EQ(alone.data.value("public_key").toString(), kNode);
    LOGOS_ASSERT_EQ(alone.data.value("signature").toString(),
                    QString("be84b09138f9c76445408520999f61e80bd96b0eaf767f370debdef67deea048c292a22767c6f47102363101eb98fe256968970f2d407685af8a60f1db527f04"));
    const Answer invited = run(kEnrolIntent, {{"program", kProgram}, {"participant_account", kParticipant}, {"referrer", kReferrer}});
    LOGOS_ASSERT_EQ(invited.data.value("signature").toString(),
                    QString("73527e846dbcd25cde66b84e46f9a73a56a5ce103a030ce98bc7cfa7e1c24dafef532ea203e4d6ea98b24e658e8e142684d6ea92796d4020808b0bf0801de706"));
}

LOGOS_TEST(the_node_signs_the_payout_opening_uplink_module_builds) {
    LOGOS_ASSERT_EQ(QString::fromLatin1(payoutMessage(QByteArray(32, '\x04'), QByteArray::fromHex(kNode.toLatin1()), QByteArray(32, '\x09'))),
                    QString("{\"blinding_factor\":\"" + kBlinding + "\",\"node\":\"" + kNode
                            + "\",\"program_account\":\"" + kProgram + "\"}"));
    const Answer payout = run(kPayoutIntent, {{"program_account", kProgram}, {"blinding_factor", kBlinding}});
    LOGOS_ASSERT_TRUE(payout.ok);
    LOGOS_ASSERT_EQ(payout.data.value("signature").toString(),
                    QString("000d8a2dc98d5797a871b80ac3aeb489553bda2f509e8d1b2f7140a2735eb8bbda7dc297c4eee6027235415d13245cd0aa495de38fc21bfb8b404b7df8ec770d"));
}

LOGOS_TEST(the_receipt_secret_is_uplinks) {
    // uplink's wallet::receipt_secret vector for [7; 32], and the module's for [1; 32].
    LOGOS_ASSERT_EQ(QString::fromLatin1(receiptSecret(QByteArray(32, '\x07')).toHex()),
                    QString("7fa048d0e5466925a9ff213b168fcb2dd08d61b6eeedf779502a136503419f30"));
    const Answer secret = run(kReceiptSecretIntent, {});
    LOGOS_ASSERT_TRUE(secret.ok);
    LOGOS_ASSERT_EQ(secret.data.value("receipt_secret").toString(),
                    QString("ef40b5fccb6d782204eacd59707bd291fc690e138c8a25605da412cffda5aa2d"));
    LOGOS_ASSERT_FALSE(secret.data.contains("signature"));
}

LOGOS_TEST(a_request_shows_this_nodes_id_and_reads_no_secret_to_do_so) {
    Prepared prepared;
    QString error;
    // A keystore with no secret half still prepares: preparing reads only the public key.
    const QByteArray publicHalf = "public_keys:\n  BlendSigning: " + kNode.toLatin1() + "\n";
    LOGOS_ASSERT_TRUE(prepare(kEnrolIntent, {{"program", kProgram}, {"participant_account", kParticipant}}, publicHalf, prepared, error));
    LOGOS_ASSERT_EQ(prepared.shown.value("node").toString(), kNode);
    LOGOS_ASSERT_EQ(prepared.shown.value("referrer").toString(), QString());
    LOGOS_ASSERT_FALSE(answer(prepared, publicHalf).ok);
}

LOGOS_TEST(malformed_requests_and_keystores_are_refused) {
    LOGOS_ASSERT_FALSE(run(kEnrolIntent, {{"program", "09"}, {"participant_account", kParticipant}}).ok);
    LOGOS_ASSERT_FALSE(run(kEnrolIntent, {{"program", kProgram}, {"participant_account", kParticipant}, {"referrer", "zz"}}).ok);
    LOGOS_ASSERT_FALSE(run(kPayoutIntent, {{"program_account", kProgram}}).ok);
    LOGOS_ASSERT_FALSE(run(QStringLiteral("wallet.send"), {}).ok);
    LOGOS_ASSERT_FALSE(handles(QStringLiteral("node.sign_anything")));
    // A keystore whose BlendSigning public key isn't its secret's: nothing is signed.
    const Answer mismatched = run(kReceiptSecretIntent, {}, keystore(kNode, QByteArray(32, '\x02')));
    LOGOS_ASSERT_FALSE(mismatched.ok);
    LOGOS_ASSERT_FALSE(run(kReceiptSecretIntent, {}, QByteArray("secret_keys:\n")).ok);
}
