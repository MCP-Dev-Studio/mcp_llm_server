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
