#pragma once

#include <QVariant>
#include <QList>
#include <string>

namespace logos {
struct CallError {
    std::string code;
    std::string message;
    std::string origin;
    bool ok() const { return code.empty(); }
};
}

struct Timeout { explicit Timeout(int) {} };
struct LogosResult {
    bool success;
    QVariant value;
    QVariant error;
};
Q_DECLARE_METATYPE(LogosResult)

// Only the module transport is replaced. Tests exercise the real view backend
// and table model, not SQLite or the SQL module's implementation.
class LogosAPIClient
{
public:
    struct Call { QString method; QVariantList arguments; };
    QList<Call> calls;
    struct Reply { QVariant value; logos::CallError error; };
    QList<Reply> replies;

    QVariant invokeRemoteMethod(const QString&, const QString& method,
                                const QVariantList& arguments, Timeout, logos::CallError* error = nullptr)
    {
        calls.append({method, arguments});
        const auto reply = replies.isEmpty() ? Reply{} : replies.takeFirst();
        if (error) *error = reply.error;
        return reply.value;
    }

    void succeed(QVariant value = {}) { replies.append({QVariant::fromValue(LogosResult{true, value, {}}), {}}); }
    void fail(const QString& error) { replies.append({QVariant::fromValue(LogosResult{false, {}, error}), {}}); }
    void failTransport(const std::string& code) { replies.append({{}, {code, "test transport failure", "sql_module"}}); }
};
