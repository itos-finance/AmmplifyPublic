/** @type {import('@tomehq/core').TomeConfig} */
export default {
  name: "Ammplify MCP",
  theme: {
    preset: "amber",
    mode: "dark",
  },
  navigation: [
    {
      group: "Getting Started",
      pages: ["index", "guides/quickstart"],
    },
    {
      group: "Setup Guides",
      pages: [
        "guides/claude-desktop",
        "guides/claude-code",
      ],
    },
    {
      group: "Tools Reference",
      pages: [
        "reference/read-tools",
        "reference/write-tools",
      ],
    },
    {
      group: "Architecture",
      pages: [
        "reference/architecture",
        "reference/networks",
      ],
    },
  ],
};
