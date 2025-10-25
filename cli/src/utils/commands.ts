/**
 * Available slash commands for autocomplete
 */

export interface CommandOption {
  command: string;
  description: string;
  category: string;
}

export const AVAILABLE_COMMANDS: CommandOption[] = [
  // Basic commands
  { command: "/help", description: "Show help message", category: "Basic" },
  { command: "/ping", description: "Check MCP gateway connectivity", category: "Basic" },
  { command: "/list", description: "List available MCP tools", category: "Basic" },
  { command: "/init", description: "Initialize MCP session", category: "Basic" },
  { command: "/call", description: "Call an MCP tool", category: "Basic" },
  { command: "/exit", description: "Exit the CLI", category: "Basic" },
  { command: "/quit", description: "Exit the CLI (alias for /exit)", category: "Basic" },
  { command: "/retry", description: "Retry authentication", category: "Basic" },

  // Service commands
  { command: "/service add", description: "Add a new service", category: "Service" },
  { command: "/service delete", description: "Delete a service", category: "Service" },
  { command: "/service monitor", description: "Monitor service status", category: "Service" },
  { command: "/service test", description: "Test a service", category: "Service" },
  { command: "/service add-groups", description: "Add groups to service", category: "Service" },
  { command: "/service remove-groups", description: "Remove groups from service", category: "Service" },
  { command: "/service create-group", description: "Create a service group", category: "Service" },
  { command: "/service delete-group", description: "Delete a service group", category: "Service" },
  { command: "/service list-groups", description: "List all service groups", category: "Service" },

  // Import commands
  { command: "/import dry", description: "Dry run import from registry", category: "Import" },
  { command: "/import apply", description: "Apply import from registry", category: "Import" },

  // User commands
  { command: "/user create-m2m", description: "Create M2M user", category: "User" },
  { command: "/user create-human", description: "Create human user", category: "User" },
  { command: "/user delete", description: "Delete a user", category: "User" },
  { command: "/user list", description: "List all users", category: "User" },
  { command: "/user list-groups", description: "List user groups", category: "User" },

  // Diagnostic commands
  { command: "/diagnostic run-suite", description: "Run diagnostic test suite", category: "Diagnostic" },
  { command: "/diagnostic run-test", description: "Run specific diagnostic test", category: "Diagnostic" },
];

/**
 * Get command suggestions based on partial input
 */
export function getCommandSuggestions(input: string): CommandOption[] {
  if (!input.startsWith("/")) {
    return [];
  }

  const normalized = input.toLowerCase();

  return AVAILABLE_COMMANDS.filter(cmd =>
    cmd.command.toLowerCase().startsWith(normalized)
  ).slice(0, 10); // Limit to 10 suggestions
}

/**
 * Get all commands for a specific category
 */
export function getCommandsByCategory(category: string): CommandOption[] {
  return AVAILABLE_COMMANDS.filter(cmd => cmd.category === category);
}
