import { test } from "node:test";
import assert from "node:assert/strict";
import { isCompleteProfile, rewriteFields } from "../src/accountMerge";

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

test("a profile counts as complete only once isUTStudent is written", () => {
    assert.equal(isCompleteProfile(null), false);
    assert.equal(isCompleteProfile({ fields: { verificationNonce: { value: "n", type: "STRING" } } }), false);
    assert.equal(isCompleteProfile({ fields: { isUTStudent: { value: 0, type: "INT64" } } }), true);
    assert.equal(isCompleteProfile({ fields: { isUTStudent: { value: 1, type: "INT64" }, firstName: { value: "Natalie", type: "STRING" } } }), true);
});
