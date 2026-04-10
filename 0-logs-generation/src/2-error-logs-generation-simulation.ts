import * as fs from 'fs';
import * as path from 'path';
import { createWriteStream, WriteStream } from 'fs';

interface ErrorLogConfig {
  outputDir: string;
  intervalSeconds: number;
  enableAllErrors: boolean;
  errorTypes: ErrorType[];
}

interface ErrorLogEntry {
  type: ErrorType;
  content: string;
  timestamp: Date;
}

enum ErrorType {
  MALFORMED_JSON = 'malformed-json',
  EMPTY_MESSAGE = 'empty-message',
  NON_JSON = 'non-json',
  LARGE_FIELD = 'large-field',
  SPECIAL_CHARS = 'special-chars',
  INVALID_FIELD_TYPE = 'invalid-field-type',
  UNPARSEABLE_TIMESTAMP = 'unparseable-timestamp',
  MISSING_REQUIRED_FIELDS = 'missing-required-fields',
  INVALID_ENCODING = 'invalid-encoding',
  CIRCULAR_REFERENCE = 'circular-reference',
  EXTREME_NESTING = 'extreme-nesting'
}

class ErrorLogGenerator {
  private streams: Map<string, WriteStream> = new Map();
  private config: ErrorLogConfig;
  private intervalId?: NodeJS.Timeout;
  private counter: number = 0;
  private errorCounts: Map<ErrorType, number> = new Map();

  constructor(config: Partial<ErrorLogConfig> = {}) {
    this.config = {
      outputDir: config.outputDir || '/1-logs-storage/error-logs',
      intervalSeconds: config.intervalSeconds || 10,
      enableAllErrors: config.enableAllErrors ?? true,
      errorTypes: config.errorTypes || Object.values(ErrorType)
    };
  }

  private initializeStreams(): void {
    // Create output directory if it doesn't exist
    if (!fs.existsSync(this.config.outputDir)) {
      fs.mkdirSync(this.config.outputDir, { recursive: true });
    }

    // Create a write stream for each error type
    for (const errorType of this.config.errorTypes) {
      const filePath = path.join(this.config.outputDir, `${errorType}.log`);
      const stream = createWriteStream(filePath, { flags: 'a' });
      this.streams.set(errorType, stream);
      this.errorCounts.set(errorType, 0);
    }
  }

  private generateMalformedJSON(): ErrorLogEntry {
    // Missing closing brace
    const content = '{"Body":"Test error message","Severity":"ERROR","Resource":{"service.name":"test-service","host.name":"test-host"},"@timestamp":"' + new Date().toISOString() + '"';
    return {
      type: ErrorType.MALFORMED_JSON,
      content: content,
      timestamp: new Date()
    };
  }

  private generateEmptyMessage(): ErrorLogEntry {
    const content = '{}';
    return {
      type: ErrorType.EMPTY_MESSAGE,
      content: content,
      timestamp: new Date()
    };
  }

  private generateNonJSON(): ErrorLogEntry {
    const content = `[${new Date().toISOString()}] This is plain text log - not JSON format at all!`;
    return {
      type: ErrorType.NON_JSON,
      content: content,
      timestamp: new Date()
    };
  }

  private generateLargeField(): ErrorLogEntry {
    const hugeBody = 'x'.repeat(100000); // 100KB field
    const content = JSON.stringify({
      Body: hugeBody,
      Severity: "ERROR",
      Resource: {
        "service.name": "test-service",
        "host.name": "test-host"
      },
      "@timestamp": new Date().toISOString()
    });
    return {
      type: ErrorType.LARGE_FIELD,
      content: content,
      timestamp: new Date()
    };
  }

  private generateSpecialChars(): ErrorLogEntry {
    const content = JSON.stringify({
      Body: "Test with special chars: \x00\x01\x02\x03\x04\x05",
      Severity: "ERROR",
      Resource: {
        "service.name": "test-service",
        "host.name": "test-host"
      },
      "@timestamp": new Date().toISOString()
    });
    return {
      type: ErrorType.SPECIAL_CHARS,
      content: content,
      timestamp: new Date()
    };
  }

  private generateInvalidFieldType(): ErrorLogEntry {
    const content = JSON.stringify({
      Body: "Valid body",
      Severity: ["ERROR", "WARNING", "INFO"], // Array instead of string
      Resource: {
        "service.name": "test-service",
        "host.name": "test-host"
      },
      "@timestamp": new Date().toISOString()
    });
    return {
      type: ErrorType.INVALID_FIELD_TYPE,
      content: content,
      timestamp: new Date()
    };
  }

  private generateUnparseableTimestamp(): ErrorLogEntry {
    const content = JSON.stringify({
      Body: "Test message",
      Severity: "INFO",
      Resource: {
        "service.name": "test-service",
        "host.name": "test-host"
      },
      "@timestamp": "not-a-valid-timestamp-format"
    });
    return {
      type: ErrorType.UNPARSEABLE_TIMESTAMP,
      content: content,
      timestamp: new Date()
    };
  }

  private generateMissingRequiredFields(): ErrorLogEntry {
    // Missing Body and Severity fields
    const content = JSON.stringify({
      Resource: {
        "service.name": "test-service",
        "host.name": "test-host"
      },
      "@timestamp": new Date().toISOString()
    });
    return {
      type: ErrorType.MISSING_REQUIRED_FIELDS,
      content: content,
      timestamp: new Date()
    };
  }

  private generateInvalidEncoding(): ErrorLogEntry {
    // Create a buffer with invalid UTF-8 sequence
    const invalidBuffer = Buffer.from([0xFF, 0xFE, 0xFD, 0xFC, 0xFB]);
    const content = invalidBuffer.toString('utf8') + '{"Body":"Valid JSON after invalid chars"}';
    return {
      type: ErrorType.INVALID_ENCODING,
      content: content,
      timestamp: new Date()
    };
  }

  private generateCircularReference(): ErrorLogEntry {
    const obj: any = {
      Body: "Test",
      Severity: "ERROR"
    };
    obj.self = obj; // Create circular reference
    const content = JSON.stringify(obj);
    return {
      type: ErrorType.CIRCULAR_REFERENCE,
      content: content,
      timestamp: new Date()
    };
  }

  private generateExtremeNesting(): ErrorLogEntry {
    let nested: any = { Body: "Deeply nested", Severity: "INFO" };
    for (let i = 0; i < 100; i++) {
      nested = { level: i, data: nested };
    }
    const content = JSON.stringify(nested);
    return {
      type: ErrorType.EXTREME_NESTING,
      content: content,
      timestamp: new Date()
    };
  }

  private getGeneratorForType(type: ErrorType): () => ErrorLogEntry {
    const generators: Record<ErrorType, () => ErrorLogEntry> = {
      [ErrorType.MALFORMED_JSON]: () => this.generateMalformedJSON(),
      [ErrorType.EMPTY_MESSAGE]: () => this.generateEmptyMessage(),
      [ErrorType.NON_JSON]: () => this.generateNonJSON(),
      [ErrorType.LARGE_FIELD]: () => this.generateLargeField(),
      [ErrorType.SPECIAL_CHARS]: () => this.generateSpecialChars(),
      [ErrorType.INVALID_FIELD_TYPE]: () => this.generateInvalidFieldType(),
      [ErrorType.UNPARSEABLE_TIMESTAMP]: () => this.generateUnparseableTimestamp(),
      [ErrorType.MISSING_REQUIRED_FIELDS]: () => this.generateMissingRequiredFields(),
      [ErrorType.INVALID_ENCODING]: () => this.generateInvalidEncoding(),
      [ErrorType.CIRCULAR_REFERENCE]: () => this.generateCircularReference(),
      [ErrorType.EXTREME_NESTING]: () => this.generateExtremeNesting()
    };
    return generators[type];
  }

  private writeLog(entry: ErrorLogEntry): Promise<void> {
    return new Promise((resolve, reject) => {
      const stream = this.streams.get(entry.type);
      if (!stream) {
        reject(new Error(`No stream found for error type: ${entry.type}`));
        return;
      }

      const logLine = entry.content + '\n';
      stream.write(logLine, (error) => {
        if (error) {
          reject(error);
        } else {
          this.errorCounts.set(entry.type, (this.errorCounts.get(entry.type) || 0) + 1);
          resolve();
        }
      });
    });
  }

  private async generateError(): Promise<void> {
    this.counter++;
    
    // Rotate through error types
    const errorType = this.config.errorTypes[this.counter % this.config.errorTypes.length];
    const generator = this.getGeneratorForType(errorType);
    const entry = generator();
    
    try {
      await this.writeLog(entry);
      this.printStatus(entry);
    } catch (error) {
      console.error(`❌ Failed to write error log: ${error}`);
    }
  }

  private printStatus(entry: ErrorLogEntry): void {
    const count = this.errorCounts.get(entry.type) || 0;
    console.log(`[${entry.timestamp.toISOString()}] ❌ Generated: ${entry.type} (Total: ${count})`);
  }

  private printSummary(): void {
    console.log('\n' + '='.repeat(60));
    console.log('📊 ERROR LOG GENERATOR SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total iterations: ${this.counter}`);
    console.log('\nErrors by type:');
    for (const [type, count] of this.errorCounts.entries()) {
      console.log(`  ${type}: ${count}`);
    }
    console.log('='.repeat(60) + '\n');
  }

  public async start(): Promise<void> {
    console.log('🚨 Error Log Generator Started');
    console.log(`📁 Output directory: ${this.config.outputDir}`);
    console.log(`⏱️  Interval: ${this.config.intervalSeconds} seconds`);
    console.log(`📝 Error types: ${this.config.errorTypes.join(', ')}`);
    console.log('\nPress Ctrl+C to stop\n');

    this.initializeStreams();
    
    // Generate errors at specified interval
    this.intervalId = setInterval(async () => {
      await this.generateError();
    }, this.config.intervalSeconds * 1000);

    // Handle graceful shutdown
    process.on('SIGINT', () => {
      console.log('\n\n🛑 Shutting down error generator...');
      if (this.intervalId) {
        clearInterval(this.intervalId);
      }
      this.printSummary();
      
      // Close all streams
      for (const stream of this.streams.values()) {
        stream.end();
      }
      
      process.exit(0);
    });
  }
}

// Parse command line arguments
const args = process.argv.slice(2);
const config: Partial<ErrorLogConfig> = {
  outputDir: process.env.ERROR_LOG_DIR || '/1-logs-storage/error-logs',
  intervalSeconds: parseInt(process.env.ERROR_INTERVAL_SECONDS || '10'),
  enableAllErrors: true
};

// Allow specific error types via command line
if (args.length > 0) {
  config.errorTypes = args.map(arg => arg as ErrorType);
  config.enableAllErrors = false;
}

// Start the generator
const generator = new ErrorLogGenerator(config);
generator.start().catch(console.error);