# Integrating AI with Flutter: Creating AI Services with LlmServer and mcp_server

![Flutter and AI Integration](https://images.unsplash.com/photo-1617040619263-41c5a9ca7521?q=80&w=2070&auto=format&fit=crop)

## Introduction

In our ongoing series about integrating AI with Flutter applications, we previously explored client-side integration with `LlmClient` and `mcp_client`. Now, it's time to dive into the server-side integration using `LlmServer` and `mcp_server`. This powerful combination allows you to provide AI capabilities as services that can be consumed by multiple clients.

This article—the fifth in our Model Context Protocol (MCP) series and the third focused on `mcp_llm`—explores how to build robust AI services that leverage the standardized MCP protocol, making your AI capabilities accessible to a wide range of client applications.

## Table of Contents

1. [Understanding LlmServer and mcp_server](#understanding-llmserver-and-mcp_server)
2. [Server-Side Integration Architecture](#server-side-integration-architecture)
3. [Setting Up the Integration](#setting-up-the-integration)
4. [Registering LLM Functions as MCP Tools](#registering-llm-functions-as-mcp-tools)
5. [Core LLM Plugins](#core-llm-plugins)
6. [AI-Based Tool Generation](#ai-based-tool-generation)
7. [Server Monitoring and Management](#server-monitoring-and-management)
8. [Next Steps](#next-steps)

## Understanding LlmServer and mcp_server

Before we dive into the integration, let's clarify the roles of these two key components:

### The Role of LlmServer

`LlmServer` is a core component from the `mcp_llm` package that serves as the server-side implementation for AI capabilities. It's responsible for:

- Communicating with Large Language Models (LLMs) like Claude, GPT, etc.
- Registering and managing AI-powered tools
- Processing queries and generating responses
- Managing plugins and extensions
- Monitoring performance and requests

It essentially exposes AI capabilities as a service, rather than embedding them directly in your client applications.

### The Role of mcp_server

`mcp_server` implements the Model Context Protocol (MCP) on the server side, allowing:

- Registration and exposure of tools to clients
- Management of resources (databases, APIs, files)
- Provision of standardized prompt templates
- Client connection and session management
- Protocol-based communication

### The Value of Integration

When integrated, these components enable:

1. Exposing LLM capabilities as standardized MCP tools
2. Centralizing AI functions for multiple clients
3. Managing API keys and credentials securely in one place
4. Dynamically generating new tools based on natural language descriptions
5. Scaling AI capabilities independently from client applications

This integration transforms AI development by creating a clear separation between the client interface and the backend AI processing, allowing for better scalability, security, and resource management.

## Server-Side Integration Architecture

Understanding the architecture of this integration is crucial for implementation:

### Integration Model

```
[Client Apps] ← HTTP/SSE → [mcp_server] ↔ [LlmServer] ← HTTP → [LLM API]
                                ↓              ↓
                        [Tools/Resources]  [Plugin Management]
```

### Communication Flow

The communication flow between components follows this pattern:

1. `mcp_server` receives requests from clients (Flutter apps, web clients, etc.)
2. If the request involves an LLM tool, it's forwarded to `LlmServer`
3. `LlmServer` processes the request and communicates with the LLM provider
4. The LLM's response is returned to `LlmServer`
5. `LlmServer` processes the response and returns the result to `mcp_server`
6. `mcp_server` sends the final result back to the client

This layered architecture creates clear separation of concerns and enables efficient scaling.

## Setting Up the Integration

Let's walk through the process of setting up an integrated AI server using `LlmServer` and `mcp_server`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_server/mcp_server.dart' as mcp;
import 'package:dotenv/dotenv.dart';

Future<void> main() async {
  // Logger setup - utility for structured server logs
  final logger = Logger.getLogger('mcp_llm.server');

  try {
    // Load environment variables - server configuration settings
    final env = DotEnv()..load();
    final apiKey = env['OPENAI_API_KEY'] ?? '';
    final serverPort = int.tryParse(env['MCP_SERVER_PORT'] ?? '8999') ?? 8999;
    final authToken = env['MCP_AUTH_TOKEN'] ?? 'test_token';
    final logLevelStr = env['LOG_LEVEL'] ?? 'info';

    // Set log level - various levels of detail for logging
    final LogLevel logLevel;
    switch (logLevelStr.toLowerCase()) {
      case 'trace': logLevel = LogLevel.trace; break;
      case 'debug': logLevel = LogLevel.debug; break;
      case 'info': logLevel = LogLevel.info; break;
      case 'warning': logLevel = LogLevel.warning; break;
      case 'error': logLevel = LogLevel.error; break;
      default: logLevel = LogLevel.info;
    }
    logger.setLevel(logLevel);

    // Verify API key - required setting for server startup
    if (apiKey.isEmpty) {
      logger.error('OPENAI_API_KEY is not set.');
      exit(1);
    }

    logger.info('Starting AI service server...');

    // Create McpLlm instance - entry point for all LLM functionality
    final mcpLlm = McpLlm();

    // Register LLM provider - support for various AI models
    mcpLlm.registerProvider('openai', OpenAiProviderFactory());
    logger.debug('OpenAI provider registered.');

    // Create MCP server - Model Context Protocol server configuration
    final mcpServer = mcp.McpServer.createServer(
      name: 'ai_service',
      version: '1.0.0',
      capabilities: mcp.ServerCapabilities(
        tools: true,
        toolsListChanged: true,
        resources: true,
        resourcesListChanged: true,
        prompts: true,
        promptsListChanged: true,
        sampling: true,
      ),
    );

    // Register custom tools - add specific functionality tools
    final pluginManager = PluginManager();

    await pluginManager.registerPlugin(EchoToolPlugin());
    await pluginManager.registerPlugin(CalculatorToolPlugin());

    // Create LlmServer - server for providing AI functionality as a service
    final llmServer = await mcpLlm.createServer(
      providerName: 'openai',  // LLM provider to use
      config: LlmConfiguration(
        apiKey: apiKey,
        model: 'gpt-4o',  // Model to use
        options: {
          'temperature': 0.3,  // Control response randomness/creativity (0-1)
          'max_tokens': 2000,  // Maximum output token limit
        },
      ),
      storageManager: MemoryStorage(),
      pluginManager: pluginManager,
      mcpServer: mcpServer,  // MCP server integration
    );

    logger.info('LlmServer has been created.');

    // Register core LLM plugins - enable basic AI functionality
    await llmServer.registerCoreLlmPlugins(
      registerCompletionTool: true,  // Text generation tool
      registerStreamingTool: true,   // Streaming response tool
      registerEmbeddingTool: true,   // Embedding generation tool
      registerRetrievalTools: true,  // Retrieval-related tools
      registerWithServer: true,      // Auto-register with MCP server
    );
    logger.info('Core LLM plugins registered.');

    // Add auto-generated tool - LLM designs/implements tool automatically
    // Executing asynchronously to avoid delaying server startup
    _generateAutomaticTool(llmServer, logger);

    // Create SSE transport - communication channel between server and clients
    final transport = mcp.McpServer.createSseTransport(
      endpoint: '/sse',
      messagesEndpoint: '/message',
      port: serverPort,
      authToken: authToken,  // Token for client authentication
    );

    // Connect MCP server with transport
    mcpServer.connect(transport);
    logger.info('MCP server connected to transport.');

    // Output server information
    logger.info('AI service running on port $serverPort.');
    logger.info('Server URL: http://localhost:$serverPort/sse');

    // Verify auth token setting
    if (authToken.isNotEmpty) {
      logger.debug('Auth token set: $authToken');
    }

    // Output available tools
    final tools = mcpServer.getTools();
    logger.info('');
    logger.info('Available tools:');
    for (final tool in tools) {
      logger.info('- ${tool.name}: ${tool.description}');
    }

    // Handle server shutdown - for Ctrl+C or other termination
    ProcessSignal.sigint.watch().listen((_) async {
      logger.info('Shutting down server...');
      await mcpLlm.shutdown();
      exit(0);
    });

    // Maintain event loop - keep server running
    try {
      logger.info('Server ready to process requests. Press Ctrl+C to shut down.');
      await Future.delayed(Duration(days: 365));
    } catch (e) {
      logger.error('Error during server execution: $e');
    }

  } catch (e, stack) {
    logger.error('Error during server startup: $e');
    logger.debug('Stack trace: $stack');
    exit(1);
  }
}

// AI-based tool generation function - LLM designs and implements tools automatically
void _generateAutomaticTool(LlmServer server, Logger logger) async {
  try {
    logger.info('Generating sentiment analysis tool...');

    // Tool description - LLM uses this description to generate the tool
    final toolDescription = """
      Create a tool that analyzes the sentiment of text. This tool should provide:
      
      1. Sentiment analysis of input text (positive, negative, neutral)
      2. Sentiment score (-1.0 to 1.0, where -1 is most negative, 1 is most positive)
      3. Extraction of key sentiment words
      4. Analysis confidence (0.0 to 1.0)
      
      It should support text in multiple languages and provide results in either text or JSON format.
      
      The tool name must be sentiment_analyzer.
      """;

    // Attempt LLM-based tool generation
    try {
      logger.info('Attempting LLM-based tool generation...');

      // Generate tool
      final success = await server.generateAndRegisterTool(
        toolDescription,
        registerWithServer: true,  // Auto-register with server
      );

      logger.info('Automatic tool generation result: ${success ? "Success" : "Failed"}');

      if (!success) {
        logger.info('Automatic generation failed...');
      }
    } catch (e) {
      logger.error('Error during tool generation: $e');

      // Handle error if direct registration is needed
      logger.info('Error...');
    }
  } catch (e) {
    logger.error('Error during sentiment analyzer tool setup: $e');
  }
}

class EchoToolPlugin extends BaseToolPlugin {
  EchoToolPlugin() : super(
    name: 'echo',
    version: '1.0.0',
    description: 'Echoes back the input message with optional transformation',
    inputSchema: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message to echo back'
        },
        'uppercase': {
          'type': 'boolean',
          'description': 'Whether to convert to uppercase',
          'default': false
        }
      },
      'required': ['message']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final message = arguments['message'] as String;
    final uppercase = arguments['uppercase'] as bool? ?? false;

    final result = uppercase ? message.toUpperCase() : message;

    Logger.getLogger('LlmServerDemo').debug(message);
    return LlmCallToolResult([
      LlmTextContent(text: result),
    ]);
  }
}

class CalculatorToolPlugin extends BaseToolPlugin {
  CalculatorToolPlugin() : super(
    name: 'calculator',
    version: '1.0.0',
    description: 'Performs basic arithmetic operations',
    inputSchema: {
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'description': 'The operation to perform (add, subtract, multiply, divide)',
          'enum': ['add', 'subtract', 'multiply', 'divide']
        },
        'a': {
          'type': 'number',
          'description': 'First number'
        },
        'b': {
          'type': 'number',
          'description': 'Second number'
        }
      },
      'required': ['operation', 'a', 'b']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final operation = arguments['operation'] as String;
    final a = (arguments['a'] as num).toDouble();
    final b = (arguments['b'] as num).toDouble();

    double result;
    switch (operation) {
      case 'add':
        result = a + b;
        break;
      case 'subtract':
        result = a - b;
        break;
      case 'multiply':
        result = a * b;
        break;
      case 'divide':
        if (b == 0) {
          throw Exception('Division by zero');
        }
        result = a / b;
        break;
      default:
        throw Exception('Unknown operation: $operation');
    }

    Logger.getLogger('LlmServerDemo').debug('$result');
    return LlmCallToolResult([
      LlmTextContent(text: result.toString()),
    ]);
  }
}
```

The code above sets up an integrated AI server with several key components:

1. **Environment configuration**: Loading API keys, port settings, and authentication tokens from environment variables
2. **McpLlm and provider setup**: Creating the main instance and registering LLM providers
3. **MCP server creation**: Setting up the MCP server with required capabilities
4. **Tool registration**: Registering basic tools like Echo and Calculator
5. **LlmServer creation**: Creating the LLM server and connecting it to the MCP server
6. **Core plugin registration**: Registering basic AI functionality as tools
7. **AI-based tool generation**: Using the LLM to generate a sentiment analysis tool automatically
8. **Transport setup**: Setting up SSE transport for client communication

## Registering LLM Functions as MCP Tools

One of the key aspects of this integration is exposing LLM functionality as MCP tools that clients can access. The provided code demonstrates two approaches to tool registration:

### 1. Plugin Registration

The sample code shows how to create tool plugins by extending the `BaseToolPlugin` class and registering them via the `PluginManager`:

```dart
// Register custom tools through PluginManager
final pluginManager = PluginManager();
await pluginManager.registerPlugin(EchoToolPlugin());
await pluginManager.registerPlugin(CalculatorToolPlugin());
```

The `EchoToolPlugin` and `CalculatorToolPlugin` classes demonstrate how to implement custom tools by:
- Defining the tool name, version, and description
- Specifying the input schema as JSON Schema
- Implementing the `onExecute` method to handle tool calls

### 2. Core LLM Plugins

The `registerCoreLlmPlugins` method automatically registers a set of core LLM capabilities as tools:

```dart
// Register core LLM plugins
await llmServer.registerCoreLlmPlugins(
  registerCompletionTool: true,  // Text generation
  registerStreamingTool: true,   // Streaming responses
  registerEmbeddingTool: true,   // Embedding generation
  registerRetrievalTools: true,  // Retrieval-related tools
  registerWithServer: true,      // Auto-register with MCP server
);
```

These core plugins expose the fundamental LLM capabilities (text generation, embeddings, etc.) as standardized tools, making them available to clients through the MCP protocol.

## Core LLM Plugins

The core LLM plugins registered through `registerCoreLlmPlugins` provide access to the following functionalities:

- **CompletionTool**: Enables text generation from prompts
- **StreamingTool**: Provides streaming responses for real-time updates
- **EmbeddingTool**: Generates vector embeddings for text
- **RetrievalTools**: Offers retrieval-augmented generation capabilities

These tools are automatically registered with the MCP server, making them available to all connected clients.

## AI-Based Tool Generation

One of the most innovative features demonstrated in the code is the ability to generate new tools automatically using the LLM itself. This is implemented in the `_generateAutomaticTool` function:

```dart
void _generateAutomaticTool(LlmServer server, Logger logger) async {
  try {
    logger.info('Generating sentiment analysis tool...');

    // Tool description - LLM uses this description to generate the tool
    final toolDescription = """
      Create a tool that analyzes the sentiment of text. This tool should provide:
      
      1. Sentiment analysis of input text (positive, negative, neutral)
      2. Sentiment score (-1.0 to 1.0, where -1 is most negative, 1 is most positive)
      3. Extraction of key sentiment words
      4. Analysis confidence (0.0 to 1.0)
      
      It should support text in multiple languages and provide results in either text or JSON format.
      
      The tool name must be sentiment_analyzer.
      """;

    // Attempt LLM-based tool generation
    try {
      logger.info('Attempting LLM-based tool generation...');

      // Generate tool
      final success = await server.generateAndRegisterTool(
        toolDescription,
        registerWithServer: true,  // Auto-register with server
      );

      logger.info('Automatic tool generation result: ${success ? "Success" : "Failed"}');

      if (!success) {
        logger.info('Automatic generation failed...');
      }
    } catch (e) {
      logger.error('Error during tool generation: $e');
      logger.info('Error...');
    }
  } catch (e) {
    logger.error('Error during sentiment analyzer tool setup: $e');
  }
}
```

This function uses the `generateAndRegisterTool` method to:
1. Send a natural language tool description to the LLM
2. Have the LLM design the tool's input schema and implementation
3. Generate executable code for the tool functionality
4. Register the resulting tool with the server

This powerful capability allows developers to create complex tools simply by describing them in natural language, greatly accelerating development.

## Server Monitoring and Management

The sample code includes several features for effective server monitoring and management:

### 1. Logging System

The code sets up a comprehensive logging system with different levels:

```dart
final logger = Logger.getLogger('mcp_llm.server');

// Set log level based on environment
final LogLevel logLevel;
switch (logLevelStr.toLowerCase()) {
  case 'trace': logLevel = LogLevel.trace; break;
  case 'debug': logLevel = LogLevel.debug; break;
  case 'info': logLevel = LogLevel.info; break;
  case 'warning': logLevel = LogLevel.warning; break;
  case 'error': logLevel = LogLevel.error; break;
  default: logLevel = LogLevel.info;
}
logger.setLevel(logLevel);
```

This logging system helps track server operations, errors, and important events.

### 2. Tool Inventory

The code lists all available tools after registration:

```dart
// Output available tools
final tools = mcpServer.getTools();
logger.info('');
logger.info('Available tools:');
for (final tool in tools) {
  logger.info('- ${tool.name}: ${tool.description}');
}
```

This provides a clear view of what capabilities are available to clients.

### 3. Graceful Shutdown

The code implements a graceful shutdown mechanism to ensure proper resource cleanup:

```dart
// Handle server shutdown - for Ctrl+C or other termination
ProcessSignal.sigint.watch().listen((_) async {
  logger.info('Shutting down server...');
  await mcpLlm.shutdown();
  exit(0);
});
```

This ensures that all resources are properly released when the server is terminated.

## Next Steps

After implementing the basic integration between `LlmServer` and `mcp_server`, there are several advanced topics you might want to explore:

1. **Multiple LLM Provider Integration**: Integrating different AI models (Claude, GPT, etc.) with MCP ecosystem
2. **MCP Plugin System Development**: Building custom tools and resources as plugins
3. **Distributed MCP Environments**: Creating complex systems with multiple MCP clients and servers
4. **Parallel Processing with MCP Tools**: Implementing parallel task execution with MCP tools
5. **Building MCP-based RAG Systems**: Implementing knowledge-based systems with document retrieval

The integration of `LlmServer` with `mcp_server` opens up numerous possibilities for building AI-powered services that can be consumed by a wide range of client applications.

## Conclusion

In this article, we've explored the integration between `LlmServer` and `mcp_server` to create powerful AI services. This server-side integration offers numerous benefits:

1. **Standardized API**: Expose AI capabilities through a standardized protocol
2. **Resource Optimization**: Process heavy AI workloads on the server, preserving client resources
3. **Centralized Management**: Manage all AI features and tools from a central location
4. **Scalability**: Easily add new AI features or tools without client-side changes
5. **Multi-Client Support**: Support various client platforms with a single server
6. **Enhanced Security**: Keep sensitive API keys and credentials on the server

The ability to automatically generate new tools using the LLM itself is particularly exciting, as it allows developers to create complex AI-powered tools using natural language descriptions instead of writing code.

By combining the client-side integration discussed in previous articles with the server-side integration presented here, you can build a complete, scalable AI ecosystem that leverages the power of the Model Context Protocol.

---

## Resources

- [mcp_llm GitHub Repository](https://github.com/app-appplayer/mcp_llm)
- [mcp_server GitHub Repository](https://github.com/app-appplayer/mcp_server)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [OpenAI API Documentation](https://platform.openai.com/docs/)
- [Flutter Documentation](https://flutter.dev/docs)

---

### Support the Developer

If you found this article helpful, please consider supporting the development of more free content through Patreon. Your support makes a big difference!

[![Support on Patreon](https://c5.patreon.com/external/logo/become_a_patron_button.png)](https://www.patreon.com/mcpdevstudio)

**Tags**: #Flutter #AI #MCP #LLM #Dart #OpenAI #ModelContextProtocol #AIIntegration #mcp_server #LlmServer