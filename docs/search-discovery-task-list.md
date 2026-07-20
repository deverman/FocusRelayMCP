# FocusRelay search and discovery checklist

Marketing operations that improve discovery without expanding the product
backlog or making the README keyword-heavy. This is a working checklist, not a
software roadmap. Links and registry support were checked on July 15, 2026.

## Recommended order

1. Publish a small landing page and connect it to Google Search Console.
2. Publish a custom-installation record to the official MCP Registry.
3. Correct or replace stale directory entries.
4. Refresh the Omni Group and Reddit announcements.
5. Submit to one carefully maintained MCP collection.

## 1. Publish the landing page

- [ ] Enable [GitHub Pages for FocusRelay](https://github.com/deverman/FocusRelayMCP/settings/pages).
- [ ] Publish a focused page that links back to the
  [canonical repository](https://github.com/deverman/FocusRelayMCP) and leads
  with the Homebrew install.
- [ ] Set the published site as the repository website in
  [repository settings](https://github.com/deverman/FocusRelayMCP/settings).
- [ ] Add the site to [Google Search Console](https://search.google.com/search-console/welcome),
  submit its sitemap, and request indexing for the home page.
- [ ] Add canonical, Open Graph, social-image, and `SoftwareApplication`
  structured-data metadata.

Ready-to-use search copy:

- **Page title:** `FocusRelay — Fast Swift OmniFocus MCP Server for macOS`
- **H1:** `Use AI to plan and update OmniFocus`
- **Meta description:** `Use AI to find, review, update, complete, and move
  OmniFocus tasks and projects. FocusRelay runs locally on macOS and installs
  with Homebrew.`
- **Primary button:** `Install FocusRelay with Homebrew`
- **Secondary button:** `View FocusRelay on GitHub`
- **Natural search phrases:** `OmniFocus MCP server`, `OmniFocus AI`, and
  `Swift OmniFocus MCP`

Recommended opening:

> FocusRelay connects AI tools to OmniFocus so you can find work, plan your
> day, and safely update tasks and projects in natural language. It is written
> in Swift for fast local performance, uses documented OmniFocus APIs, and
> installs with Homebrew.

## 2. Publish to the official MCP Registry

### Verified distribution decision

The official Registry does **not** have a Homebrew package type. Its supported
package registries are npm, PyPI, NuGet, Cargo, OCI, and MCPB, as listed in the
[official requirements](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/official-registry-requirements.md#restricted-registry-base-urls).

The Registry does, however, explicitly support a
[server with a custom installation path](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/generic-server-json.md#server-with-custom-installation-path).
That record can use `websiteUrl` without pretending FocusRelay is an npm or
cross-platform package. The Registry will provide discovery; the linked page
will provide the real Homebrew installation.

Recommended approach:

- [x] Add a custom-installation record named
  `io.github.deverman/focusrelay`.
- [x] Point `websiteUrl` to the
  [README installation section](https://github.com/deverman/FocusRelayMCP#install-the-omnifocus-mcp-server-with-homebrew)
  until the landing page exists.
- [x] Follow the [official publishing guide](https://modelcontextprotocol.io/registry/quickstart).
- [x] Install the publisher with `brew install mcp-publisher`.
- [x] Run `mcp-publisher login github`, then use the displayed code at
  [GitHub device authorization](https://github.com/login/device).
- [x] Run `mcp-publisher publish server.json` from the repository root.
- [x] Confirm the result through the
  [official Registry API search](https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.deverman%2Ffocusrelay).
- [ ] Automate later using the
  [official GitHub Actions guide](https://modelcontextprotocol.io/registry/github-actions),
  but only after one manual publication succeeds.

The canonical metadata is [`server.json`](../server.json). Do not add a
`package.json`: FocusRelay is distributed as a native Swift/Homebrew program,
not an npm package.

Published July 15, 2026. The public Registry API returned one matching record
with the correct name, version `0.10.0-beta`, title, and installation URL.

If the preview Registry rejects its documented custom-installation form, report
the mismatch through the
[Registry issue form](https://github.com/modelcontextprotocol/registry/issues/new/choose)
and continue with the directories below. Do not add an npm wrapper or OCI image
just to satisfy a listing: npm would add a misleading runtime layer, and a
container cannot provide normal access to the local OmniFocus app.

Future alternative, only if client-managed installation becomes valuable:

- [ ] Evaluate an MCPB artifact attached to GitHub Releases. MCPB is the
  Registry-supported format for a prebuilt binary and requires no language
  toolchain, but it adds packaging work and depends on client support. See the
  [official MCPB requirements](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/package-types.mdx#mcpb-packages).

## 3. Correct directory listings

Use this correction packet after the consolidated edit commands ship in a
Homebrew release. Until then, keep directory listings aligned with the current
released catalog rather than advertising source-only commands.

> **FocusRelay** is a free, open-source OmniFocus MCP server and CLI for macOS.
> It is written in Swift, runs locally, and uses documented OmniFocus APIs. The
> current build provides nine focused MCP tools: seven read tools and two
> consolidated edit tools for safely updating tasks and projects. Install it
> with Homebrew; it is not an npm package and is not cross-platform. License:
> MIT. Repository:
> https://github.com/deverman/FocusRelayMCP

Install commands:

```bash
brew tap deverman/focus-relay
brew trust --formula deverman/focus-relay/focusrelay
brew install focusrelay
```

- [ ] Review the live
  [MCP Servers listing](https://mcpservers.org/servers/deverman/FocusRelayMCP)
  and request corrections if it differs from the packet above.
- [ ] Search [MCPgee for FocusRelay](https://www.google.com/search?q=site%3Amcpgee.com+FocusRelay)
  and remove or correct any `npx` install or unsupported-platform claims. No
  FocusRelay URL appeared in MCPgee's current sitemap when checked.
- [ ] Search [MCPpedia for FocusRelay](https://www.google.com/search?q=site%3Amcpedia.io+FocusRelay+OR+site%3Amcppedia.io+FocusRelay)
  and correct zero-tool, missing-license, or read-only claims.
- [ ] Search [SkillsIndex for FocusRelay](https://www.google.com/search?q=site%3Askillsindex.ai+FocusRelay+OR+site%3Askillsindex.com+FocusRelay)
  and correct stale mirrors. Its domains were not reliably reachable during
  this review, so verify the listing still exists before spending time on it.
- [ ] Prefer maintained directories that link to the canonical repository.
  Do not spend time fixing an abandoned auto-generated mirror unless it ranks
  for a relevant search.

## 4. Refresh community announcements

- [ ] Find the existing post through the
  [Omni Group forum search](https://discourse.omnigroup.com/search?q=FocusRelayMCP)
  and add a release update rather than starting a duplicate thread.
- [ ] Find the existing posts through
  [Reddit search](https://www.reddit.com/search/?q=FocusRelayMCP) and update or
  comment on them. Use the [OmniFocus subreddit](https://www.reddit.com/r/omnifocus/)
  only when a new release post adds useful information for that community.

Ready-to-post update:

> **FocusRelay 0.10 beta: AI can now safely update OmniFocus**
>
> FocusRelay can now do more than answer questions about your OmniFocus data.
> AI tools can update task and project details, dates, flags, tags, and location;
> complete or reopen tasks and projects; and change project status while
> previewing or verifying important changes. Task dropping and restoration are
> not yet supported. FocusRelay remains a fast, local Swift app that uses
> documented OmniFocus APIs and keeps its MCP tool set deliberately small to
> reduce context use. Install it with Homebrew and see examples at
> https://github.com/deverman/FocusRelayMCP

Before posting, replace `0.10 beta` if a newer release is current and confirm
every listed update still works in the release UAT. Do not post the nine-tool
claim before the consolidated edit commands are available through Homebrew.

## 5. Submit to maintained collections

- [ ] Read the
  [awesome-mcp-servers contribution guide](https://github.com/punkpeye/awesome-mcp-servers/blob/main/CONTRIBUTING.md).
- [ ] Search the
  [collection for FocusRelay](https://github.com/punkpeye/awesome-mcp-servers/search?q=FocusRelay&type=code)
  before opening a pull request.
- [ ] If absent, use the repository's
  [fork and pull-request flow](https://github.com/punkpeye/awesome-mcp-servers/fork)
  to propose this concise entry:

> **FocusRelay** — Fast, local Swift MCP server and CLI for reading and safely
> updating OmniFocus on macOS. Homebrew installation; MIT licensed.

## 6. Earn useful external links

- [ ] Publish the architecture story: `Building a Fast OmniFocus MCP Server in
  Swift with Omni Automation`.
  - Explain why the native Swift server is fast and lightweight.
  - Explain how the bridge runs in Omni Automation and uses documented APIs.
  - Show the Homebrew installation and one read/write workflow.
- [ ] Publish the measurement story: `How We Benchmark an OmniFocus MCP Server
  Without Trading Correctness for Speed`.
  - Describe dataset scale by order of magnitude, not one person's library.
  - Explain semantic gates, latency measurement, and reliability checks.
  - Avoid an unsupported “fastest” claim; publish reproducible evidence.
- [ ] Share those articles with relevant Swift, MCP, and OmniFocus communities
  and link to the landing page with descriptive text.

## 7. Measure results

- [ ] Record a monthly baseline in this file or a private marketing tracker:
  - GitHub best-match position for `omnifocus mcp`.
  - Google visibility for `OmniFocus MCP server`, `Swift OmniFocus MCP`, and
    branded FocusRelay searches.
  - Referral traffic, stars, and Homebrew install interest.
- [ ] Review [GitHub traffic](https://github.com/deverman/FocusRelayMCP/graphs/traffic)
  and [Google Search Console](https://search.google.com/search-console/welcome)
  after 30 and 90 days.
- [ ] Add more README content only when the data shows a discovery gap.

## Later decision: repository name

- [ ] Reconsider `FocusRelay-OmniFocus-MCP` only after the release campaign.
- [ ] Before renaming, audit Homebrew formula URLs, release automation, badges,
  package metadata, documentation, and high-value external links.
- [ ] Rename only if the expected GitHub search benefit is worth the migration
  and existing links will redirect safely.
