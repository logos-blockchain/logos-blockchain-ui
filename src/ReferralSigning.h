#pragma once

#include <QByteArray>
#include <QString>
#include <QVariantMap>

// What the node does for the Uplink referral programme (logos-blockchain/uplink), when another
// app asks through an intent and the user approves: sign its enrolment, sign a payout code, or
// hand over its receipt secret. The node's Blend signing key never leaves this app.
//
// Requests carry named values, never bytes to sign: the messages are built here, with this
// node filled in, so a request can't get anything else signed. The formats are uplink's
// (programs/referral/core and wallet/src/receipt.rs at 8021f33) and uplink_module's.
namespace referral_signing {

inline const QString kEnrolIntent = QStringLiteral("node.sign_referral_enrolment");
inline const QString kPayoutIntent = QStringLiteral("node.sign_referral_payout");
inline const QString kReceiptSecretIntent = QStringLiteral("node.referral_receipt_secret");

bool handles(const QString& intent);

// A request, checked and ready to show: what the user approves, and what will be signed.
struct Prepared {
    QString intent;
    QByteArray node;      // this node's Blend signing public key (its ID in the programme)
    QByteArray message;   // what gets signed; empty for the receipt secret
    QVariantMap shown;    // for the approval dialog: hex fields, by name
};

struct Answer {
    bool ok = false;
    QVariantMap data;     // {signature, public_key} or {receipt_secret, public_key}, hex
    QString error;
};

// The node's ID from the keystore's public half; empty if there's none. Reads no secret.
QByteArray blendSigningPublicKey(const QByteArray& keystoreYaml);

// Checks `params` for `intent` and builds what would be signed, for the node in the keystore.
// `error` says what's wrong when it returns false.
bool prepare(const QString& intent, const QVariantMap& params, const QByteArray& keystoreYaml,
             Prepared& out, QString& error);

// Carries out a prepared request with the keystore's Blend signing key. The key and every
// copy of it are wiped before returning.
Answer answer(const Prepared& prepared, const QByteArray& keystoreYaml);

// The formats, exposed for tests.
QByteArray enrolmentMessage(const QByteArray& program, const QByteArray& node,
                            const QByteArray& participant, const QByteArray& referrer);
QByteArray payoutMessage(const QByteArray& blindingFactor, const QByteArray& node,
                         const QByteArray& program);
QByteArray receiptSecret(const QByteArray& nodeSecret);

} // namespace referral_signing
