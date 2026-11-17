import { list, lookup, num, str, type CKRecord } from "./cloudkit/client";
import { parseCrop } from "./videoCrop";
import { ASSET_FIELDS, RECORD_TYPES, type ShareTypeID } from "./sharePost";
import { PHOTO_EQUIPMENT } from "./shareOptions";

/**
 * Editing a post from the website (server only): who may edit it, and the post's saved
 * values turned back into the Share form's fields, so the form opens filled in.
 */

/** The post's record if `userRecordName` made it, with its Share type. */
export async function ownedPost(postID: string, userRecordName: string): Promise<{ record: CKRecord; type: ShareTypeID } | null> {
  if (!/^[0-9A-Fa-f-]{36}$/.test(postID) || !userRecordName) return null;
  const record = await lookup(postID);
  if (!record || str(record, "userID") !== userRecordName) return null;
  const type = (Object.keys(RECORD_TYPES) as ShareTypeID[]).find((t) => RECORD_TYPES[t] === record.recordType);
  return type ? { record, type } : null;
}

/** Whether the record holds a file for an asset field, in CloudKit or as an R2 link. */
export function recordHasFile(r: CKRecord, field: string): boolean {
  const v = r.fields[field]?.value;
  if (Array.isArray(v) ? v.length > 0 : !!v) return true;
  return !!str(r, `${field}URL`) || list(r, `${field}URLs`).length > 0;
}

/** Which form field holds each asset field's files. */
const FORM_FILE: Record<ShareTypeID, Record<string, string>> = {
  film: { filmVideo: "video", filmThumbnail: "thumbnail", filmTrailer: "trailer", filmBTS: "bts", filmStills: "stills" },
  music: { musicAudio: "tracks", musicCover: "cover", musicVideo: "musicVideo" },
  performance: { reelVideo: "videos", reelThumbnail: "thumbnail", reelStills: "photos" },
  photography: { photographyImages: "photos", photographyThumbnail: "photos" },
  design: { designImages: "images", designVideo: "video" },
  project: { projectPoster: "poster", projectSlides: "slides" },
  event: { eventFlyer: "flyer" },
};

/** "Role: Name" entries plus their profile IDs, as the form's credit rows. */
function credits(r: CKRecord, key: string, idsKey: string) {
  const ids = list(r, idsKey);
  return list(r, key).flatMap((entry, i) => {
    const at = entry.indexOf(":");
    const name = (at < 0 ? entry : entry.slice(at + 1)).trim();
    return name ? [{ role: at < 0 ? "" : entry.slice(0, at).trim(), name, ...(ids[i] ? { profileID: ids[i] } : {}) }] : [];
  });
}
/** Saved credits, or the form's empty row when there are none. */
const rows = (found: ReturnType<typeof credits>, empty: { role: string; name: string }[]) => (found.length ? found : empty);

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "Jun 15, 2026" → "2026-06-15". */
function isoDay(text: string): string {
  const m = /^([A-Z][a-z]{2}) (\d{1,2}), (\d{4})$/.exec(text.trim());
  const month = m ? MONTHS.indexOf(m[1]) : -1;
  return m && month >= 0 ? `${m[3]}-${String(month + 1).padStart(2, "0")}-${m[2].padStart(2, "0")}` : "";
}

/** A moment as the form's local day and time (Austin time, as the site shows events). */
const partsFmt = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Chicago", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});
function local(ms: number | undefined): { day: string; time: string } {
  if (!ms) return { day: "", time: "" };
  const p = Object.fromEntries(partsFmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}

/** The post's saved values as the Share form's fields (the keys its useDraftField calls use). */
export function formFields(type: ShareTypeID, r: CKRecord): Record<string, unknown> {
  switch (type) {
    case "film":
      return {
        title: str(r, "filmTitle"), logline: str(r, "filmLogline"), studio: str(r, "filmStudio"), genres: list(r, "filmGenres"),
        year: str(r, "filmReleaseYear"), rating: str(r, "filmAgeRating") || "PG", festivalBound: num(r, "filmFestivalBound") === 1,
        cast: rows(credits(r, "filmCast", "filmCastIDs"), [{ role: "", name: "" }]), crew: credits(r, "filmCrew", "filmCrewIDs"),
        videoCrop: parseCrop(str(r, "filmVideoCrop")),
      };
    case "music": {
      const link = (k: string) => str(r, k);
      return {
        title: str(r, "musicTitle"), artist: str(r, "musicArtist"), category: str(r, "musicCategory"), genres: list(r, "musicGenres"),
        year: str(r, "musicReleaseYear"), explicit: num(r, "musicExplicit") === 1, lyrics: str(r, "lyrics"),
        links: Object.fromEntries(
          [["Spotify", link("musicSpotifyLink")], ["Apple Music", link("musicAppleMusicLink")], ["YouTube Music", link("youtubeMusicLink")], ["SoundCloud", link("soundcloudLink")]]
            .filter(([, v]) => v),
        ),
        recording: credits(r, "musicRecording", "musicRecordingIDs"), production: credits(r, "musicProduction", "musicProductionIDs"),
      };
    }
    case "performance":
      return {
        title: str(r, "reelTitle"), description: str(r, "reelDescription"), category: str(r, "reelType"), year: str(r, "reelReleaseYear"),
        featured: list(r, "featuredWorkManual"), cast: rows(credits(r, "orderedCast", "orderedCastIDs"), [{ role: "", name: "" }]),
      };
    case "photography": {
      const equipment: Record<string, string> = Object.fromEntries(PHOTO_EQUIPMENT.map((e) => [e.key, ""]));
      for (const entry of list(r, "photographyGear")) {
        const at = entry.indexOf(": ");
        if (at < 0) continue;
        const label = entry.slice(0, at);
        const e = PHOTO_EQUIPMENT.find((x) => x.label === label || (label === "Other" && x.key === "accessories"));
        if (e) equipment[e.key] = entry.slice(at + 2);
      }
      return {
        title: str(r, "photographyTitle"), description: str(r, "photographyDescription"), year: str(r, "photographyReleaseYear"), equipment,
        credits: rows(credits(r, "orderedCrew", "orderedCrewIDs"), [{ role: "Photographer", name: "" }]),
      };
    }
    case "design":
      return {
        title: str(r, "designTitle"), description: str(r, "designDescription"), category: str(r, "designCategory"), year: str(r, "designReleaseYear"),
        credits: rows(credits(r, "orderedCrew", "orderedCrewIDs"), [{ role: "Designer", name: "" }]), videoCrop: parseCrop(str(r, "designVideoCrop")),
      };
    case "project": {
      const [start = "", end = ""] = str(r, "projectShootDatesText").split(" - ").map(isoDay);
      const needed = (k: string) => (list(r, k).length ? list(r, k) : [""]);
      return {
        title: str(r, "projectTitle"), logline: str(r, "projectDescription"), category: str(r, "projectType"), writers: str(r, "writers"),
        genre: list(r, "projectGenres")[0] ?? "", shootStart: start, shootEnd: end, release: isoDay(str(r, "projectReleaseDateText")),
        castNeeded: needed("projectCastNeeded"), crewNeeded: needed("projectCrewNeeded"),
        castAssembled: rows(credits(r, "projectCastAssembled", "projectCastAssembledIDs"), [{ role: "", name: "" }]),
        crewAssembled: credits(r, "projectCrewAssembled", "projectCrewAssembledIDs"),
      };
    }
    case "event": {
      const start = local(num(r, "eventStartTime"));
      const end = local(num(r, "eventEndTime"));
      const showings = list(r, "eventShowtimes").flatMap((entry) => {
        const [a, b] = entry.split("|").map((x) => Date.parse(x));
        if (!Number.isFinite(a)) return [];
        const s = local(a);
        return [{ day: s.day, start: s.time, end: Number.isFinite(b) ? local(b).time : "21:00" }];
      });
      return {
        title: str(r, "eventTitle"), host: str(r, "eventHost"), description: str(r, "eventDescription"), category: str(r, "eventCategory"),
        location: str(r, "eventLocationText"), lineup: list(r, "eventLineup").join(", "), expectations: str(r, "eventExpectations"),
        applicationLink: str(r, "eventApplicationURL"), ticketLink: str(r, "eventTicketsURL"),
        day: start.day, startTime: start.time || "18:00", endTime: end.time || "20:00", startDate: start.day, endDate: end.day,
        ...(showings.length ? { showings } : {}),
      };
    }
  }
}

/** The form fields that already have files on the post (they stay unless replaced). */
export function keptFormFiles(type: ShareTypeID, r: CKRecord): string[] {
  const kept = Object.keys(ASSET_FIELDS[type]).filter((f) => recordHasFile(r, f) && FORM_FILE[type][f]).map((f) => FORM_FILE[type][f]);
  // A Script post's file lives on its Script record.
  if (type === "project" && str(r, "projectType") === "Script") kept.push("script");
  return [...new Set(kept)];
}
