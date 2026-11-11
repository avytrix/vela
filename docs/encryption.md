# Encrypted paths (Tier C): hide file content even from people who clone

Tiers A and B cannot stop `git clone`. Tier C closes that gap **for file content**: files under protected folders are
stored encrypted, so a clone holds ciphertext. It is built from three parts:

1. **`client/vela-crypt`** (needs `age`, `git`, `curl`, `bash`). A git clean/smudge filter encrypts on commit and
   decrypts on checkout, using the **SSH keys people already have on GitLab** (public keys are served at
   `https://GITLAB/USERNAME.keys`; the private key never leaves the user's machine). GitLab tokens are not used: the
   server stores only a hash of them, so they cannot be keys.
2. **The server hook** rejects a push, from anyone including admins, that puts plaintext under an encrypted folder. Add the
   folders to the policy variable: `{"enabled":true,"rules":[...],"encrypted":["secrets"]}`.
3. **Write rules** (Tier A or B) still decide who may change those files.

## Set up (once per project)

```bash
vela-crypt init                                        # in every clone: wires up the filter
vela-crypt protect secrets                             # writes the .gitattributes line
vela-crypt recipients https://git.example.com alice bob   # public keys of everyone who may read
git add .gitattributes .vela && git commit -m "protect secrets/"   # then add "encrypted": ["secrets"] to the policy
```

Each person runs `vela-crypt init` once, and `vela-crypt sync` after each pull.

## What a user who is NOT a recipient gets

Their clone has the files as unreadable ciphertext. `vela-crypt sync` then leaves those files **out of their working
tree** (git sparse-checkout, kept in `.git/info`, never pushed), which is the per-user "ignore" for files they cannot
read. `.gitignore` itself cannot do this, because it does not apply to files that are already tracked. They cannot
change what they cannot decrypt, and the write rules reject a push that tries.

## What does not work, said plainly

- **GitLab's web pages cannot show these files to anyone, authorized users included.** The server only ever holds
  ciphertext, so the web editor, merge request diffs, search and blame show unreadable text or "binary". Reviewers
  read the change **locally**: `git diff` and `git log -p` show plaintext for people with a key.
- **File names, folder structure, sizes and commit messages stay visible.**
- **Taking access away is not retroactive.** Remove someone from `.vela/recipients` and re-encrypt, and new content is
  safe, but they keep what they already cloned.
- **Plaintext already in history stays readable** until the history is rewritten (`git filter-repo`), and any secret that
  was there must be rotated.
- Merge conflicts inside an encrypted file cannot be resolved by GitLab; resolve them locally.

If you need names hidden too, or the web UI to work, put the folder in its own project instead:
[split-secrets.md](./split-secrets.md).
