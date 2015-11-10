$pubnub = Pubnub.new(
    subscribe_key: Rails.application.secrets.pubnub_subscribe_key,
    publish_key: Rails.application.secrets.pubnub_publish_key,
    secret_key: Rails.application.secrets.pubnub_secret_key,
    auth_key: Rails.application.secrets.pubnub_auth_key
)

$pubnub.grant(
    read: true,
    write: false,
    auth_key: nil,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'notifications.*',
    http_sync: true,
    ttl: 0
)