#pragma once
#include "logos_api_client.h"

class LogosAPI
{
public:
    LogosAPIClient client;
    LogosAPIClient* getClient(const QString&) { return &client; }
};
