import { getAnthropicClient } from "./anthropicClient.js";
import { anthropicTools, buildTaskContext, executeMappedTool, mapToolCall } from "./tools.js";
import type { TaskContext } from "../tasks/types.js";

export interface AgentMessage {
  role: "user" | "assistant" | "system";
  content: string;
}

export interface AgentConfig {
  gatewayUrl: string;
  gatewayBaseUrl: string;
  gatewayToken?: string;
  backendToken?: string;
  model?: string;
}

export interface AgentResult {
  messages: AgentMessage[];
  toolOutputs: Array<{ name: string; output: string; isError?: boolean }>;
}

const DEFAULT_MODEL = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514";

type ConversationEntry = {
  role: string;
  content: any;
  tool_use_id?: string;
};

export async function runAgentTurn(history: AgentMessage[], config: AgentConfig): Promise<AgentResult> {
  const client = getAnthropicClient();

  const systemMessages = history.filter((msg) => msg.role === "system").map((msg) => msg.content);
  const systemPrompt = [buildSystemPrompt(), ...systemMessages].join("\n\n");

  const messages = history
    .filter((msg) => msg.role === "user" || msg.role === "assistant")
    .map((msg) => ({ role: msg.role, content: msg.content })) as ConversationEntry[];

  const context: TaskContext = buildTaskContext(config.gatewayUrl, config.gatewayBaseUrl, config.gatewayToken, config.backendToken);

  const finalMessages: AgentMessage[] = [];
  const toolOutputs: Array<{ name: string; output: string; isError?: boolean }> = [];

  let toolIteration = 0;
  let conversation: ConversationEntry[] = [...messages];
  if (conversation.length === 0) {
    conversation.push({ role: "user", content: history.filter((msg) => msg.role !== "system").map((msg) => msg.content).join("\n") || "Hello." });
  }

  while (toolIteration < 5) {
    const response = await (client as any).beta.tools.messages.create({
      model: config.model ?? DEFAULT_MODEL,
      system: systemPrompt,
      messages: conversation,
      max_tokens: 8192,
      tools: anthropicTools
    });

    const outputBlocks = (response.content ?? []) as any[];
    const toolCalls = outputBlocks.filter((block) => block.type === "tool_use");
    const textBlocks = outputBlocks.filter((block) => block.type === "text");

    if (toolCalls.length === 0) {
      const content = textBlocks.map((block) => (block.type === "text" ? block.text : "")).join("\n");
      finalMessages.push({ role: "assistant", content });
      break;
    }

    const assistantMessage: ConversationEntry = { role: "assistant", content: response.content };
    conversation = [...conversation, assistantMessage];

    for (const call of toolCalls) {
      const invocation = mapToolCall(call);
      const result = await executeMappedTool(invocation, config.gatewayUrl, context);
      toolOutputs.push({ name: call.name, output: result.output, isError: result.isError });
      conversation = [
        ...conversation,
        {
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: call.id,
              content: result.output
            }
          ]
        }
      ];
    }

    toolIteration += 1;
  }

  if (toolIteration >= 5) {
    finalMessages.push({ role: "assistant", content: "Reached tool usage limit without final response." });
  }

  return { messages: finalMessages, toolOutputs };
}

function buildSystemPrompt(): string {
  return `You are the MCP Registry Assistant, an AI assistant with direct access to MCP (Model Context Protocol) Registry tools.

# Your Capabilities

You have access to powerful tools for managing and interacting with MCP servers:

## mcp_command Tool
Call MCP gateway commands directly:
- **ping**: Check connectivity to MCP servers
- **list**: List available MCP tools and resources
- **call**: Execute specific MCP tools with arguments
- **init**: Initialize new MCP connections

## registry_task Tool
Execute administrative tasks via slash commands:
- Service management (add, remove, configure servers)
- Import servers from registries
- User and access management
- System diagnostics and health checks

## read_docs Tool
Search and read project documentation:
- Search by keywords: Use search_query parameter
- Read specific file: Use file_path parameter (e.g., 'auth.md', 'quick-start.md')
- List all docs: Call with no parameters

**When to use**: When users ask about features, setup, configuration, authentication, troubleshooting, or any project-related questions. Use this tool to find relevant documentation and provide accurate answers based on the docs content.

# Your Behavior

**Be helpful and proactive:**
- Provide clear, well-formatted responses using markdown
- Explain what you're doing and why
- Anticipate follow-up questions
- Offer suggestions for next steps

**Tool usage:**
- Use tools whenever the user needs to perform actions
- Call tools with precise, correct parameters
- After tool execution, summarize the results in a user-friendly way
- **IMPORTANT**: Do NOT show raw tool output to users unless there's an error
- Only include raw tool output when debugging errors or when explicitly requested
- If a tool fails, explain what went wrong, show the error output, and suggest alternatives

**Response formatting:**
- Keep formatting simple and terminal-friendly
- Use clear sections with line breaks
- Use bullet points (•) for lists
- For code/JSON, present it cleanly without complex formatting
- Break down complex operations into numbered steps
- Avoid heavy use of markdown syntax (**, ##, etc.) - keep it minimal
- **IMPORTANT**: Wrap file paths and reserved words (like command names, tool names, service names) in backticks to highlight them
- Examples: \`/service add\`, \`/mcpgw/mcp\`, \`ping\`, \`list\`, \`.oauth-tokens/ingress.json\`

**Security:**
- Never expose raw tokens, secrets, or credentials
- Redact sensitive information from outputs
- Warn users about potentially destructive operations

**Context awareness:**
- Remember the conversation history
- Reference previous tool outputs when relevant
- Build on earlier context to provide coherent assistance

# Example Interactions

When listing tools:
Let me check what tools are available on the MCP server...
[calls mcp_command with list]

Great! I found 5 tools:
  • fetch_url - Retrieve content from web URLs
  • search_files - Search for files in the workspace
  • read_file - Read file contents
  • write_file - Create or update files
  • execute_command - Run shell commands

What would you like to do with these tools?

When executing commands:
I'll ping the MCP gateway to check connectivity...
[calls mcp_command with ping]

✓ Connection successful! The gateway is responding normally.

Remember: You are a knowledgeable, helpful assistant. Keep responses clear, concise, and easy to read in a terminal environment.

When answering questions about the project, refer to the following documentation context if you are unable to answer the question.

# Project Documentation

The project contains documentation in the following README files:

- **README.md**: Main project documentation - Enterprise-Ready Gateway for AI Development Tools
- **credentials-provider/agentcore-auth/README.md**: OAuth2 token generation for Amazon Bedrock AgentCore Gateways
- **docs/README.md**: MkDocs-based documentation setup and structure
- **keycloak/README.md**: Keycloak identity and access management setup with Docker
- **metrics-service/docs/README.md**: Centralized metrics collection and aggregation system for MCP Gateway
- **scripts/README.md**: Utility scripts for MCP Gateway and Registry management
- **servers/fininfo/README.md**: Financial information MCP server using Polygon.io API
- **servers/mcpgw/README.md**: MCP server for interacting with the main Registry API
- **servers/realserverfaketools/README.md**: Demo MCP server with fake tools for testing
- **tests/README.md**: Comprehensive test suite for validating functionality


`;
}
