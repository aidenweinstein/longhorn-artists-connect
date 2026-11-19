import { NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { assetUploadURLs, lookup, queryAll, uploadAsset } from "@/lib/cloudkit/client";
import { getAccount, getAllPosts } from "@/lib/cloudkit/content";
import { isCredited } from "@/lib/account";
import {
  abortMultipartUpload,
  completeMultipartUpload,
  createMultipartUpload,
  deleteObject,
  getObject,
  isR2Configured,
  listObjects,
  listUnfinishedUploads,
  objectSize,
  partUploadURLs,
  publicURLFor,
} from "@/lib/r2";

/**
 * TEMPORARY, development only: checks the R2 setup step by step (keys, multipart upload,
 * size-locked part URLs, public address). Delete this folder once uploads work.
 */
export async function GET(request: Request) {
  if (process.env.NODE_ENV !== "development") return new NextResponse("Not found", { status: 404 });
  if (new URL(request.url).searchParams.has("cloudkit")) {
    // An upload URL for a thumbnail, as startPost gets one (nothing is saved with it).
    const [url] = await assetUploadURLs([{ recordType: "FilmSubmission", recordName: randomUUID().toUpperCase(), fieldName: "filmThumbnail" }]);
    return NextResponse.json({ cloudkitUploadURL: url });
  }
  const speed = Number(new URL(request.url).searchParams.get("speed"));
  if (speed > 0 && speed <= 64 * 1024 * 1024) {
    // One size-locked part URL, to time an upload from the browser (aborted afterwards by the 1-day rule).
    const key = `checks/speed-${Date.now()}.bin`;
    const uploadID = await createMultipartUpload(key, "application/octet-stream");
    return NextResponse.json({ url: partUploadURLs(key, uploadID, [speed], 600)[0], key, uploadID });
  }
  if (new URL(request.url).searchParams.has("latest")) {
    // The newest films: did a post save, and with what?
    const films = await queryAll("FilmSubmission", 2000);
    films.sort((a, b) => (b.created?.timestamp ?? 0) - (a.created?.timestamp ?? 0));
    return NextResponse.json(
      films.slice(0, 3).map((r) => ({
        id: r.recordName,
        created: r.created?.timestamp,
        title: r.fields.filmTitle?.value,
        isApproved: r.fields.isApproved?.value,
        filmVideoURL: r.fields.filmVideoURL?.value,
        hasThumb: !!r.fields.filmThumbnail,
        userID: r.fields.userID?.value,
        schoolID: r.fields.schoolID?.value,
      })),
    );
  }
  const feedcheck = new URL(request.url).searchParams.get("feedcheck");
  if (feedcheck) {
    const { posts } = await getAllPosts();
    const post = posts.find((p) => p.id === feedcheck);
    const account = post?.creatorProfileID ? await getAccount(post.creatorProfileID.replace(/^UserProfile_/, "")) : null;
    return NextResponse.json({
      inFeedList: !!post,
      postCount: posts.length,
      credits: post?.details?.creditGroups,
      byline: post?.details?.byline,
      mainCredits: post?.mainCredits,
      account: account && { name: account.name, profileID: account.profileID },
      credited: post && account ? isCredited(post, account) : null,
      recordCredits: await lookup(feedcheck).then((r) => r && Object.fromEntries(Object.entries(r.fields).filter(([k]) => /Cast|Crew|submittedBy|Studio/.test(k)))),
    });
  }
  const remove = new URL(request.url).searchParams.get("delete");
  if (remove?.startsWith("posts/")) {
    await deleteObject(remove);
    return NextResponse.json({ deleted: remove, stillThere: (await objectSize(remove)) !== null });
  }
  if (new URL(request.url).searchParams.has("posts")) {
    // What's stored under posts/ (finished uploads and unfinished ones).
    const [objects, unfinished] = await Promise.all([listObjects("posts/"), listUnfinishedUploads("posts/")]);
    return NextResponse.json({ objects, unfinished });
  }
  const steps: Record<string, unknown> = { configured: isR2Configured() };
  if (!steps.configured) return NextResponse.json(steps);
  const key = `checks/r2-check-${Date.now()}.txt`;
  const body = "hello from nexus";
  let uploadID = "";
  try {
    uploadID = await createMultipartUpload(key, "text/plain");
    steps.createUpload = "ok";
    const [url] = partUploadURLs(key, uploadID, [body.length], 600);
    // For the browser test: a second upload whose part the browser sends itself.
    const browserKey = `checks/r2-browser-${Date.now()}.txt`;
    const browserUpload = await createMultipartUpload(browserKey, "text/plain");
    steps.browserTest = { key: browserKey, uploadID: browserUpload, url: partUploadURLs(browserKey, browserUpload, [body.length], 600)[0], body };
    if (new URL(request.url).searchParams.has("browserOnly")) return NextResponse.json(steps);
    const put = await fetch(url, { method: "PUT", body, headers: { "content-length": String(body.length) } });
    steps.uploadPart = { status: put.status, etag: put.headers.get("etag"), error: put.ok ? undefined : (await put.text()).slice(0, 400) };
    if (!put.ok) return NextResponse.json(steps);
    await completeMultipartUpload(key, uploadID, [{ partNumber: 1, etag: put.headers.get("etag") ?? "" }]);
    steps.complete = "ok";
    steps.size = await objectSize(key);
    const pub = await fetch(publicURLFor(key));
    steps.publicURL = { status: pub.status, text: (await pub.text()).slice(0, 100) };
    // R2 → CloudKit, as publishPost moves small files (an unsaved asset; CloudKit discards it).
    const { bytes, contentType } = await getObject(key);
    const receipt = await uploadAsset("FilmSubmission", randomUUID().toUpperCase(), "filmThumbnail", bytes, contentType);
    steps.movedToCloudKit = typeof (receipt.value as { receipt?: unknown }).receipt === "string";
    await deleteObject(key);
    steps.cleanedUp = true;
  } catch (error) {
    steps.error = String(error).slice(0, 600);
    if (uploadID) await abortMultipartUpload(key, uploadID);
  }
  return NextResponse.json(steps);
}
