#include "ReferralSigning.h"

#include <QCryptographicHash>
#include <QList>
#include <QRegularExpression>

#include <cstring>

#include <openssl/crypto.h>
#include <openssl/evp.h>

namespace referral_signing {
namespace {

// uplink: programs/referral/core (AUTHORIZATION_DOMAIN) and wallet/src/receipt.rs.
const QByteArray kAuthorizationDomain("Uplink/AuthorizeParticipant/v1\0", 31);
const QByteArray kReceiptSecretDomain("Uplink/ReceiptSecret/v1\0", 24);
const QByteArray kBlendSigning("BlendSigning");

void wipe(QByteArray& bytes)
{
    if (!bytes.isEmpty())
        OPENSSL_cleanse(bytes.data(), size_t(bytes.size()));
    bytes.clear();
}

// 32 bytes from 64 hex characters, or empty. fromHex alone skips bad characters.
QByteArray bytes32(const QString& hex)
{
    static const QRegularExpression kHex(QStringLiteral("^[0-9a-fA-F]{64}$"));
    return kHex.match(hex).hasMatch() ? QByteArray::fromHex(hex.toLatin1()) : QByteArray();
}

bool isHex64(const QByteArray& value)
{
    if (value.size() != 64)
        return false;
    for (const char c : value)
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            return false;
    return true;
}

// The value of `title` under the top-level `section` of the node's keystore.yaml (node 0.3.1:
// two levels, "section:" then "  Title: value"), without its tag ("!Ed25519 ") or quotes.
// Read by hand rather than through a YAML library, in place, so the only copy of a secret
// value is the one returned, which the caller wipes.
QByteArray keystoreValue(const QByteArray& yaml, const QByteArray& section, const QByteArray& title)
{
    const char* const text = yaml.constData();
    const qsizetype size = yaml.size();
    bool inSection = false;
    for (qsizetype start = 0; start < size;) {
        qsizetype end = yaml.indexOf('\n', start);
        if (end < 0)
            end = size;
        qsizetype last = end;   // one past the line's last character, without "\r"
        if (last > start && text[last - 1] == '\r')
            --last;
        if (last > start && text[start] != ' ' && text[start] != '\t') {
            // A top-level key: "section:".
            inSection = last - start == section.size() + 1 && text[last - 1] == ':'
                && std::memcmp(text + start, section.constData(), size_t(section.size())) == 0;
        } else if (inSection) {
            qsizetype at = start;
            while (at < last && (text[at] == ' ' || text[at] == '\t'))
                ++at;
            if (last - at > title.size() && std::memcmp(text + at, title.constData(), size_t(title.size())) == 0
                    && text[at + title.size()] == ':') {
                at += title.size() + 1;
                while (at < last && text[at] == ' ')
                    ++at;
                if (at < last && text[at] == '!') {   // a tag: "!Ed25519 <value>"
                    while (at < last && text[at] != ' ')
                        ++at;
                    while (at < last && text[at] == ' ')
                        ++at;
                }
                qsizetype stop = last;
                while (stop > at && text[stop - 1] == ' ')
                    --stop;
                if (stop - at >= 2 && (text[at] == '"' || text[at] == '\'') && text[stop - 1] == text[at]) {
                    ++at;
                    --stop;
                }
                return QByteArray(text + at, stop - at);
            }
        }
        start = end + 1;
    }
    return {};
}

QString hex(const QByteArray& bytes)
{
    return QString::fromLatin1(bytes.toHex());
}

QByteArray sha256(const QByteArray& data)
{
    return QCryptographicHash::hash(data, QCryptographicHash::Sha256);
}

// Ed25519 over `message` with the 32-byte seed, checked against `node` before it's returned.
QByteArray sign(const QByteArray& seed, const QByteArray& node, const QByteArray& message)
{
    QByteArray signature(64, '\0');
    EVP_PKEY* key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, nullptr,
                                                 reinterpret_cast<const unsigned char*>(seed.constData()), 32);
    if (!key)
        return {};
    size_t length = 64;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    const bool signedOk = EVP_DigestSignInit(ctx, nullptr, nullptr, nullptr, key) == 1
        && EVP_DigestSign(ctx, reinterpret_cast<unsigned char*>(signature.data()), &length,
                          reinterpret_cast<const unsigned char*>(message.constData()), size_t(message.size())) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);   // OpenSSL wipes its copy of the key
    if (!signedOk || length != 64)
        return {};

    EVP_PKEY* pub = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr,
                                                reinterpret_cast<const unsigned char*>(node.constData()), 32);
    EVP_MD_CTX* vctx = EVP_MD_CTX_new();
    const bool verified = pub && EVP_DigestVerifyInit(vctx, nullptr, nullptr, nullptr, pub) == 1
        && EVP_DigestVerify(vctx, reinterpret_cast<const unsigned char*>(signature.constData()), 64,
                            reinterpret_cast<const unsigned char*>(message.constData()), size_t(message.size())) == 1;
    EVP_MD_CTX_free(vctx);
    EVP_PKEY_free(pub);
    return verified ? signature : QByteArray();
}

// The public key an Ed25519 seed belongs to.
QByteArray publicKeyOf(const QByteArray& seed)
{
    EVP_PKEY* key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, nullptr,
                                                 reinterpret_cast<const unsigned char*>(seed.constData()), 32);
    if (!key)
        return {};
    QByteArray pub(32, '\0');
    size_t length = 32;
    const bool ok = EVP_PKEY_get_raw_public_key(key, reinterpret_cast<unsigned char*>(pub.data()), &length) == 1;
    EVP_PKEY_free(key);
    return ok && length == 32 ? pub : QByteArray();
}

} // namespace

bool handles(const QString& intent)
{
    return intent == kEnrolIntent || intent == kPayoutIntent || intent == kReceiptSecretIntent;
}

QByteArray blendSigningPublicKey(const QByteArray& keystoreYaml)
{
    const QByteArray value = keystoreValue(keystoreYaml, "public_keys", kBlendSigning);
    return isHex64(value) ? QByteArray::fromHex(value) : QByteArray();
}

// "Uplink/AuthorizeParticipant/v1\0" ‖ borsh(ParticipantAuthorizationV1 { program, node,
// participant, referrer: Option<NodeId> }): 128 bytes without a referrer, 160 with one.
QByteArray enrolmentMessage(const QByteArray& program, const QByteArray& node,
                            const QByteArray& participant, const QByteArray& referrer)
{
    QByteArray message = kAuthorizationDomain + program + node + participant;
    if (referrer.isEmpty())
        message.append('\0');
    else
        message.append('\1').append(referrer);
    return message;
}

// The payout code's opening as uplink_module signs it: compact JSON, keys sorted, hex.
QByteArray payoutMessage(const QByteArray& blindingFactor, const QByteArray& node, const QByteArray& program)
{
    return "{\"blinding_factor\":\"" + blindingFactor.toHex() + "\",\"node\":\"" + node.toHex()
        + "\",\"program_account\":\"" + program.toHex() + "\"}";
}

QByteArray receiptSecret(const QByteArray& nodeSecret)
{
    QByteArray preimage = kReceiptSecretDomain + nodeSecret;
    const QByteArray secret = sha256(preimage);
    wipe(preimage);
    return secret;
}

bool prepare(const QString& intent, const QVariantMap& params, const QByteArray& keystoreYaml,
             Prepared& out, QString& error)
{
    out = Prepared{intent, blendSigningPublicKey(keystoreYaml), {}, {}};
    if (out.node.isEmpty()) {
        error = QStringLiteral("This node has no Blend signing key in its keystore.");
        return false;
    }
    out.shown.insert(QStringLiteral("node"), hex(out.node));
    const auto field = [&](const char* name, bool optional = false) -> QByteArray {
        const QString value = params.value(QString::fromLatin1(name)).toString().trimmed();
        if (optional && value.isEmpty())
            return {};
        const QByteArray bytes = bytes32(value);
        if (bytes.isEmpty() && error.isEmpty())
            error = QStringLiteral("The request's %1 is not 32 bytes of hex.").arg(QString::fromLatin1(name));
        return bytes;
    };

    if (intent == kEnrolIntent) {
        const QByteArray program = field("program");
        const QByteArray participant = field("participant_account");
        const QByteArray referrer = field("referrer", true);
        if (!error.isEmpty())
            return false;
        out.message = enrolmentMessage(program, out.node, participant, referrer);
        out.shown.insert(QStringLiteral("program"), hex(program));
        out.shown.insert(QStringLiteral("participant_account"), hex(participant));
        out.shown.insert(QStringLiteral("referrer"), hex(referrer));
        return true;
    }
    if (intent == kPayoutIntent) {
        const QByteArray program = field("program_account");
        const QByteArray blinding = field("blinding_factor");
        if (!error.isEmpty())
            return false;
        out.message = payoutMessage(blinding, out.node, program);
        out.shown.insert(QStringLiteral("program_account"), hex(program));
        out.shown.insert(QStringLiteral("blinding_factor"), hex(blinding));
        return true;
    }
    if (intent == kReceiptSecretIntent)
        return true;
    error = QStringLiteral("Not a referral request.");
    return false;
}

Answer answer(const Prepared& prepared, const QByteArray& keystoreYaml)
{
    Answer result;
    QByteArray secretHex = keystoreValue(keystoreYaml, "secret_keys", kBlendSigning);
    QByteArray seed = isHex64(secretHex) ? QByteArray::fromHex(secretHex) : QByteArray();
    wipe(secretHex);
    // Matched by public key, not just title: a keystore whose BlendSigning entries disagree
    // signs nothing.
    if (seed.isEmpty() || publicKeyOf(seed) != prepared.node) {
        wipe(seed);
        result.error = QStringLiteral("This node's Blend signing key could not be read.");
        return result;
    }
    const QString publicKey = hex(prepared.node);
    if (prepared.intent == kReceiptSecretIntent) {
        QByteArray secret = receiptSecret(seed);
        result.data = {{QStringLiteral("receipt_secret"), hex(secret)}, {QStringLiteral("public_key"), publicKey}};
        wipe(secret);
        result.ok = true;
    } else {
        const QByteArray signature = sign(seed, prepared.node, prepared.message);
        if (signature.isEmpty())
            result.error = QStringLiteral("Signing failed.");
        else {
            result.data = {{QStringLiteral("signature"), hex(signature)}, {QStringLiteral("public_key"), publicKey}};
            result.ok = true;
        }
    }
    wipe(seed);
    return result;
}

} // namespace referral_signing
