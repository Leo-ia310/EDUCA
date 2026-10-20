// Browser-controlled subscriptions are untrusted network destinations.
// All network sends run in Node; the legacy Edge entry point only enqueues.
export function parsePushSubscription(raw: unknown): {
    endpoint: string;
    keys: {
        p256dh: string;
        auth: string;
    };
} {
    let value: any;
    try {
        value = typeof raw === 'string' ? JSON.parse(raw) : raw;
    }
    catch {
        throw Error('push_subscription_invalid');
    }
    if (!value || typeof value.endpoint !== 'string')
        throw Error('push_subscription_invalid');
    let url: URL;
    try {
        url = new URL(value.endpoint);
    }
    catch {
        throw Error('push_subscription_invalid');
    }
    const host = url.hostname.toLowerCase();
    const trusted = host === 'fcm.googleapis.com' || host === 'push.services.mozilla.com' || host.endsWith('.push.services.mozilla.com') || host.endsWith('.push.apple.com') || host.endsWith('.notify.windows.com') || host.endsWith('.wns.windows.com');
    if (!trusted || url.protocol !== 'https:' || url.username || url.password || url.hash || url.port && url.port !== '443')
        throw Error('push_destination_rejected');
    const key = (name: string, length: number) => {
        const text = value.keys?.[name];
        if (typeof text !== 'string' || !/^[A-Za-z0-9_-]+={0,2}$/.test(text))
            throw Error('push_subscription_invalid');
        let decoded: Buffer;
        try {
            decoded = Buffer.from(text, 'base64url');
        }
        catch {
            throw Error('push_subscription_invalid');
        }
        if (decoded.length !== length || name === 'p256dh' && decoded[0] !== 4)
            throw Error('push_subscription_invalid');
        return text;
    };
    return { endpoint: url.href, keys: { p256dh: key('p256dh', 65), auth: key('auth', 16) } };
}
