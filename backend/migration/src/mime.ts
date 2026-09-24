/**
 * Container detection from file bytes.
 *
 * Ported from CloudKitWebServices.containerExtension(forHeaderBytes:isAudio:)
 * (CloudKitWebServices.swift:198-219), which the app runs at playback time on
 * every track because CloudKit's CDN types files by filename and the stored
 * `musicAudioExt` is unreliable — most production music records carry none, and
 * some carry one that disagrees with the file. A wrong type produced AVFoundation
 * error -11828 "Cannot Open".
 *
 * Running it ONCE here, at migration time, is the point: the result is written to
 * post_media.mime_type and set as the Storage object's Content-Type, so neither
 * client ever has to guess again.
 */

export interface DetectedType {
    extension: string;
    mime: string;
}

const BY_EXTENSION: Record<string, string> = {
    mp3: 'audio/mpeg',
    m4a: 'audio/mp4',
    wav: 'audio/wav',
    aiff: 'audio/aiff',
    flac: 'audio/flac',
    caf: 'audio/x-caf',
    mov: 'video/quicktime',
    mp4: 'video/mp4',
    jpg: 'image/jpeg',
    png: 'image/png',
    heic: 'image/heic',
    webp: 'image/webp',
    gif: 'image/gif',
    pdf: 'application/pdf',
};

export function mimeForExtension(ext: string): string {
    return BY_EXTENSION[ext.toLowerCase()] ?? 'application/octet-stream';
}

function ascii(bytes: Buffer, start: number, end: number): string {
    return bytes.subarray(start, end).toString('ascii');
}

/**
 * Identifies a container from a file's leading bytes. `isAudio` disambiguates
 * the MP4 family, exactly as the Swift version does: an audio-only MP4 must be
 * served as audio/mp4 (.m4a), not video/mp4.
 */
export function detectType(bytes: Buffer, isAudio: boolean): DetectedType | null {
    if (bytes.length < 12) return null;

    // ID3 tag or a raw MPEG audio frame sync (11 set bits) => MP3.
    if (ascii(bytes, 0, 3) === 'ID3') return { extension: 'mp3', mime: 'audio/mpeg' };
    if (bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xe0) === 0xe0) {
        return { extension: 'mp3', mime: 'audio/mpeg' };
    }

    if (ascii(bytes, 4, 8) === 'ftyp') {
        const brand = ascii(bytes, 8, 12);
        if (brand.startsWith('qt')) return { extension: 'mov', mime: 'video/quicktime' };
        if (brand.startsWith('M4A') || brand.startsWith('M4B')) {
            return { extension: 'm4a', mime: 'audio/mp4' };
        }
        return isAudio
            ? { extension: 'm4a', mime: 'audio/mp4' }
            : { extension: 'mp4', mime: 'video/mp4' };
    }

    if (ascii(bytes, 0, 4) === 'RIFF') {
        // Could be WAV or AVI; the app only ever produced WAV audio.
        return { extension: 'wav', mime: 'audio/wav' };
    }
    if (ascii(bytes, 0, 4) === 'FORM') return { extension: 'aiff', mime: 'audio/aiff' };
    if (ascii(bytes, 0, 4) === 'fLaC') return { extension: 'flac', mime: 'audio/flac' };
    if (ascii(bytes, 0, 4) === 'caff') return { extension: 'caf', mime: 'audio/x-caf' };

    // Images — not handled by the Swift version (it only sniffed audio), but the
    // migration uploads images too and they need correct types.
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
        return { extension: 'jpg', mime: 'image/jpeg' };
    }
    if (ascii(bytes, 1, 4) === 'PNG') return { extension: 'png', mime: 'image/png' };
    if (ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 12) === 'WEBP') {
        return { extension: 'webp', mime: 'image/webp' };
    }
    if (ascii(bytes, 4, 8) === 'ftyp' && ascii(bytes, 8, 12).startsWith('hei')) {
        return { extension: 'heic', mime: 'image/heic' };
    }
    if (ascii(bytes, 0, 4) === '%PDF') return { extension: 'pdf', mime: 'application/pdf' };

    return null;
}

/** Fallback when sniffing fails, based on what the field is supposed to hold. */
export function fallbackType(kind: string): DetectedType {
    switch (kind) {
        case 'video':
        case 'trailer':
            return { extension: 'mov', mime: 'video/quicktime' };
        case 'audio':
            return { extension: 'm4a', mime: 'audio/mp4' };
        case 'script':
            return { extension: 'pdf', mime: 'application/pdf' };
        default:
            return { extension: 'jpg', mime: 'image/jpeg' };
    }
}
