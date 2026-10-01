const crypto = require('crypto');
const { Buffer } = require('buffer');
const { promisify } = require('util');
const scrypt = promisify(crypto.scrypt);
const options = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

const Passwords = {
    newId: () => crypto.randomBytes(16).toString('hex'),
    async hash(code) {
        if (typeof code !== 'string' || Buffer.byteLength(code, 'utf8') > 256) throw new Error('INVALID_CODE');
        const salt = crypto.randomBytes(16).toString('hex');
        const key = await scrypt(code, salt, 32, options);
        return `scrypt$${salt}$${key.toString('hex')}`;
    },
    async verify(code, encoded) {
        if (typeof code !== 'string' || Buffer.byteLength(code, 'utf8') > 256 || typeof encoded !== 'string') return false;
        const match = /^scrypt\$([a-f0-9]{32})\$([a-f0-9]{64})$/.exec(encoded);
        if (!match) return false;
        const key = await scrypt(code, match[1], 32, options);
        return crypto.timingSafeEqual(key, Buffer.from(match[2], 'hex'));
    }
};

if (typeof exports === 'function') {
    exports('NewId', Passwords.newId);
    exports('HashPassword', (code, callback) => {
        Passwords.hash(code).then(value => setImmediate(() => callback(true, value)),
            () => setImmediate(() => callback(false, null)));
    });
    exports('VerifyPassword', (code, hash, callback) => {
        Passwords.verify(code, hash).then(value => setImmediate(() => callback(true, value)),
            () => setImmediate(() => callback(false, false)));
    });
} else {
    module.exports = Passwords;
}
