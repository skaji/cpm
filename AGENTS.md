# Codex Instructions

## Git and GitHub

- Write all git commit messages in English.
- Always add this trailer to every git commit message:

  Co-authored-by: Codex <267193182+codex@users.noreply.github.com>

- Create regular pull requests, not draft pull requests.
- Write pull request titles and descriptions in English.
- Keep pull request descriptions concise. Focus on why the change is being made
  and what outcome is expected, rather than listing everything that changed.
- Do not add section headings such as "Summary" by default.
- Do not include test results in pull request descriptions.

## Perl Code and Tests

- Put tests under `xt/`.
- Test file names must start with a number.
- Start every Perl file (`.pl`, `.pm`, `.t`) with these pragmas:

  ```perl
  use v5.24;
  use warnings;
  use experimental qw(lexical_subs signatures);
  ```

- Use signatures for every subroutine, including anonymous subroutines:

  ```perl
  subtest foo => sub () {
      ...
  };
  ```
