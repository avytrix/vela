# Keeping a folder out of everyone's clone: give it its own project

vela cannot stop `git clone` (see the [README](../README.md#the-one-limit-you-must-know-about)). If a folder
must stay secret from some people who can clone the main project, move it into a **separate project** and
include it as a submodule. GitLab then checks access on the secret project itself, using its normal permissions.

1. Create a project, for example `myapp-secrets`, and give access only to the people who need it.
2. Move the folder's history into it (keep history with `git filter-repo --path secrets/ --path-rename secrets/:`)
   or just copy the files if the history is not needed.
3. In the main project: `git rm -r secrets && git submodule add git@gitlab.example.com:group/myapp-secrets.git secrets`, then commit.
4. People without access to `myapp-secrets` see an empty `secrets/` folder after `git submodule update`; the clone
   never contained the files.

**Remove the old files from history too.** Anyone who already cloned, and every old commit, still has them. Rewrite
the history of the main project (`git filter-repo --path secrets/ --invert-paths`), rotate any secret that was in it,
and ask everyone to re-clone.

Trade-offs: two projects to manage, and a change spanning both needs two merge requests. In return, hiding is real.
