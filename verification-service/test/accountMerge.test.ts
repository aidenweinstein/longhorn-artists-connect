import { test } from "node:test";
import assert from "node:assert/strict";
import { profileFill, rewriteFields } from "../src/accountMerge";

test("rewrites raw and UserProfile_ mentions, in strings and lists", () => {
    const out = rewriteFields(
        {
            userID: { value: "web_abc", type: "STRING" },
            submittedBy: { value: "Manuela", type: "STRING" },
            orderedCastIDs: { value: ["", "UserProfile_web_abc", "UserProfile_other"], type: "STRING_LIST" },
            isApproved: { value: 1, type: "INT64" },
        },
        "web_abc",
        "_app123",
    );
    assert.deepEqual(out, {
        userID: { value: "_app123", type: "STRING" },
        orderedCastIDs: { value: ["", "UserProfile__app123", "UserProfile_other"], type: "STRING_LIST" },
    });
});

test("leaves records that don't mention the account alone", () => {
    assert.deepEqual(rewriteFields({ userID: { value: "web_abcd", type: "STRING" } }, "web_abc", "_x"), {});
});

test("fills only empty app profile fields, never private ones or assets", () => {
    const fill = profileFill(
        {
            bio: { value: "Actor in Austin", type: "STRING" },
            major: { value: "RTF", type: "STRING" },
            firstName: { value: "Manu", type: "STRING" },
            verificationNonce: { value: "n", type: "STRING" },
            profileImage: { value: { downloadURL: "x" }, type: "ASSETID" },
        },
        { firstName: { value: "Manuela", type: "STRING" }, major: { value: "", type: "STRING" } },
    );
    assert.deepEqual(fill, { bio: { value: "Actor in Austin", type: "STRING" }, major: { value: "RTF", type: "STRING" } });
});
