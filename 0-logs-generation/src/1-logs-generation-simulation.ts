import * as fs from 'fs';
import * as path from 'path';

interface ParsedLogEntry {
  Resource: { [key: string]: any };
  Body: string;
  Severity: string;
  Attributes: { [key: string]: any };
}

interface LogEntryWithTimestamp extends ParsedLogEntry {
  '@timestamp': string;
}

class LogsGenerationSimulator {
  private parsedLogsDir: string;
  private outputLogsDir: string;
  private filenames: string[];
  private isRunning: boolean = true;
  private repeat: boolean = false;

  constructor(parsedLogsDir: string, outputLogsDir: string, filenames: string[], repeat: boolean = false) {
    this.parsedLogsDir = parsedLogsDir;
    this.outputLogsDir = outputLogsDir;
    this.filenames = filenames;
    this.repeat = repeat;
  }

  /**
   * Read all parsed logs from a specific file
   */
  private async readParsedLogs(filename: string): Promise<ParsedLogEntry[]> {
    const filePath = path.join(this.parsedLogsDir, filename);
    
    try {
      const content = await fs.promises.readFile(filePath, 'utf-8');
      const logs = JSON.parse(content);
      
      if (!Array.isArray(logs)) {
        console.warn(`Warning: ${filename} does not contain an array of logs`);
        return [];
      }
      
      return logs;
    } catch (error) {
      console.error(`Error reading ${filename}:`, error);
      return [];
    }
  }

  /**
   * Add current timestamp to a log entry (timestamp at the beginning)
   */
  private addTimestamp(log: ParsedLogEntry): LogEntryWithTimestamp {
    return {
      '@timestamp': new Date().toISOString(),
      ...log
    };
  }

  /**
   * Format a log entry as a string for writing to .log file
   */
  private formatLogEntry(log: LogEntryWithTimestamp): string {
    return JSON.stringify(log) + '\n';
  }

  /**
   * Append a single log to its respective .log file
   */
  private async appendSingleLog(filename: string, log: LogEntryWithTimestamp): Promise<void> {
    const logFilename = filename.replace('.json', '.log');
    const outputPath = path.join(this.outputLogsDir, logFilename);
    
    try {
      await fs.promises.mkdir(this.outputLogsDir, { recursive: true });
      await fs.promises.appendFile(outputPath, this.formatLogEntry(log), 'utf-8');
    } catch (error) {
      console.error(`Error appending to ${outputPath}:`, error);
      throw error;
    }
  }

  /**
   * Clear existing log files before starting
   */
  public async clearLogFiles(): Promise<void> {
    console.log('Clearing existing log files...');
    
    for (const filename of this.filenames) {
      const logFilename = filename.replace('.json', '.log');
      const outputPath = path.join(this.outputLogsDir, logFilename);
      
      try {
        await fs.promises.access(outputPath, fs.constants.F_OK);
        await fs.promises.unlink(outputPath);
        console.log(`✓ Cleared: ${outputPath}`);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
          console.error(`Error clearing ${outputPath}:`, error);
        }
      }
    }
    console.log('---');
  }

  /**
   * Setup signal handlers for graceful shutdown
   */
  private setupSignalHandlers(): void {
    const shutdown = () => {
      console.log('\n\n⚠ Received shutdown signal. Stopping log generation...');
      this.isRunning = false;
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  }

  /**
   * Get statistics for each file
   */
  private getFileStats(positions: Map<string, number>, totalLogsPerFile: Map<string, number>): string {
    const stats: string[] = [];
    for (const [filename, position] of positions.entries()) {
      const shortName = filename.replace('.json', '');
      const total = totalLogsPerFile.get(filename) || 0;
      
      if (this.repeat) {
        const cycle = Math.floor(position / total);
        const currentPos = position % total;
        if (cycle > 0) {
          stats.push(`${shortName}:${currentPos}/${total} (cycle ${cycle})`);
        } else {
          stats.push(`${shortName}:${position}/${total}`);
        }
      } else {
        stats.push(`${shortName}:${position}/${total}`);
      }
    }
    return stats.join(', ');
  }

  /**
   * Simulate real-life log generation with continuous streaming
   */
  public async simulateContinuousStreaming(
    logsPerSecond: number = 30
  ): Promise<void> {
    console.log('=== REAL-TIME LOG GENERATION SIMULATION ===');
    console.log(`Target rate: ${logsPerSecond} logs/second (${(logsPerSecond/this.filenames.length).toFixed(1)} logs/second per file)`);
    console.log(`Files: ${this.filenames.join(', ')}`);
    console.log(`Repeat mode: ${this.repeat ? 'ENABLED (will cycle through logs)' : 'DISABLED (will stop when logs exhausted)'}`);
    console.log('---');

    // Read all logs from all files
    const allLogsMap: Map<string, ParsedLogEntry[]> = new Map();
    let totalLogsAvailable = 0;
    
    for (const filename of this.filenames) {
      const logs = await this.readParsedLogs(filename);
      allLogsMap.set(filename, logs);
      totalLogsAvailable += logs.length;
      console.log(`Loaded ${logs.length} logs from ${filename}`);
    }
    
    console.log(`Total logs available: ${totalLogsAvailable}`);
    console.log('---');
    
    if (totalLogsAvailable === 0) {
      console.error('No logs found to stream!');
      return;
    }
    
    // Setup signal handlers for graceful shutdown
    this.setupSignalHandlers();
    
    // Keep track of consumed logs for each file
    const consumedCounts: Map<string, number> = new Map();
    const totalLogsPerFile: Map<string, number> = new Map();
    
    for (const [filename, logs] of allLogsMap.entries()) {
      consumedCounts.set(filename, 0);
      totalLogsPerFile.set(filename, logs.length);
    }
    
    // Calculate timing
    const intervalMs = 1000 / logsPerSecond;
    
    console.log(`Log generation strategy:`);
    console.log(`  - Interval between logs: ${intervalMs.toFixed(2)}ms`);
    console.log(`  - Round-robin across ${this.filenames.length} files`);
    console.log(`  - Each file gets ~${(logsPerSecond/this.filenames.length).toFixed(1)} logs/second`);
    if (!this.repeat) {
      console.log(`  - Will stop after ${totalLogsAvailable} total logs (all unique logs consumed)`);
    }
    console.log('---');
    console.log('Starting continuous log generation...');
    console.log('Press Ctrl+C to stop\n');
    
    let logCount = 0;
    let startTime = Date.now();
    let lastReportTime = startTime;
    let fileIndex = 0;
    let allFilesExhausted = false;
    
    // Continue until interrupted or all logs exhausted
    while (this.isRunning && !allFilesExhausted) {
      const currentTime = Date.now();
      
      // Get the next file to write to (round-robin)
      const filename = this.filenames[fileIndex % this.filenames.length];
      const logs = allLogsMap.get(filename);
      const consumed = consumedCounts.get(filename) || 0;
      const totalLogs = totalLogsPerFile.get(filename) || 0;
      
      // Check if this file has logs available
      let logAvailable = false;
      let log: ParsedLogEntry | undefined;
      
      if (this.repeat) {
        // In repeat mode, always available (circular)
        if (logs && logs.length > 0) {
          const position = consumed % logs.length;
          log = logs[position];
          logAvailable = true;
          consumedCounts.set(filename, consumed + 1);
        }
      } else {
        // In non-repeat mode, stop when all logs are consumed
        if (logs && consumed < logs.length) {
          log = logs[consumed];
          logAvailable = true;
          consumedCounts.set(filename, consumed + 1);
        }
      }
      
      if (logAvailable && log) {
        const logWithTimestamp = this.addTimestamp(log);
        await this.appendSingleLog(filename, logWithTimestamp);
        logCount++;
        
        // Check if all files are exhausted (only in non-repeat mode)
        if (!this.repeat) {
          let allExhausted = true;
          for (const fname of this.filenames) {
            const consumedCount = consumedCounts.get(fname) || 0;
            const totalCount = totalLogsPerFile.get(fname) || 0;
            if (consumedCount < totalCount) {
              allExhausted = false;
              break;
            }
          }
          allFilesExhausted = allExhausted;
          
          if (allFilesExhausted) {
            console.log('\n✓ All logs have been consumed! Stopping generation.');
            break;
          }
        }
        
        // Log progress periodically (every second)
        if (currentTime - lastReportTime >= 1000) {
          const elapsedSeconds = (currentTime - startTime) / 1000;
          const avgRate = logCount / elapsedSeconds;
          
          console.log(`[${new Date().toISOString()}] Stats: ${logCount} logs written | ` +
            `Rate: ${avgRate.toFixed(1)} logs/sec | ` +
            `Files: ${this.getFileStats(consumedCounts, totalLogsPerFile)}`);
          
          lastReportTime = currentTime;
        }
      } else if (!this.repeat && !logAvailable) {
        // If no log available and not in repeat mode, we should stop
        console.log(`\n⚠ File ${filename} has no more logs. Stopping generation.`);
        allFilesExhausted = true;
        break;
      }
      
      // Move to next file
      fileIndex++;
      
      // Calculate next execution time for rate control
      const nextExecutionTime = startTime + (logCount * intervalMs);
      const currentTimeMs = Date.now();
      const waitTime = Math.max(0, nextExecutionTime - currentTimeMs);
      
      // Wait for the appropriate interval
      if (waitTime > 0 && this.isRunning && !allFilesExhausted) {
        await this.delay(waitTime);
      }
    }
    
    const endTime = Date.now();
    const totalSeconds = (endTime - startTime) / 1000;
    const avgRate = totalSeconds > 0 ? logCount / totalSeconds : 0;
    
    console.log('---');
    console.log(`✓ Log generation completed!`);
    console.log(`  Total logs written: ${logCount}`);
    console.log(`  Total time: ${totalSeconds.toFixed(2)} seconds`);
    console.log(`  Average rate: ${avgRate.toFixed(1)} logs/second`);
    console.log(`  Target rate: ${logsPerSecond} logs/second`);
    if (totalSeconds > 0) {
      console.log(`  Efficiency: ${((avgRate / logsPerSecond) * 100).toFixed(1)}%`);
    }
    
    // Show consumption summary
    console.log('---');
    console.log('Consumption summary:');
    for (const filename of this.filenames) {
      const consumed = consumedCounts.get(filename) || 0;
      const total = totalLogsPerFile.get(filename) || 0;
      
      if (this.repeat) {
        const cycles = Math.floor(consumed / total);
        const remaining = consumed % total;
        if (cycles > 0) {
          console.log(`  ${filename}: ${consumed} logs written (${cycles} full cycle(s) + ${remaining}/${total} logs)`);
        } else {
          console.log(`  ${filename}: ${consumed}/${total} logs written (${((consumed/total)*100).toFixed(1)}%)`);
        }
      } else {
        console.log(`  ${filename}: ${consumed}/${total} logs written (${((consumed/total)*100).toFixed(1)}%)`);
      }
    }
  }

  /**
   * Utility function for delay
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  let logsPerSecond = 30;
  let repeat = false;
  
  for (const arg of args) {
    if (arg.startsWith('--logspersec=')) {
      logsPerSecond = parseInt(arg.split('=')[1]);
      if (isNaN(logsPerSecond)) {
        console.error('Error: --logspersec must be a number');
        process.exit(1);
      }
    } else if (arg === '--repeat') {
      repeat = true;
    } else if (arg === '--help' || arg === '-h') {
      console.log(`
Usage: npx ts-node 1-logs-generation-simulation.ts [OPTIONS]

Options:
  --logspersec=NUM    Number of logs to generate per second (default: 30)
  --repeat            Repeat logs cyclically when all logs are consumed
  --help, -h          Show this help message

Examples:
  # Generate 300 logs per second, stop when all logs are consumed
  npx ts-node 1-logs-generation-simulation.ts --logspersec=300
  
  # Generate 100 logs per second, repeat logs cyclically
  npx ts-node 1-logs-generation-simulation.ts --logspersec=100 --repeat
  
  # Generate default 30 logs per second
  npx ts-node 1-logs-generation-simulation.ts
      `);
      process.exit(0);
    } else {
      console.error(`Unknown option: ${arg}`);
      console.log('Use --help for usage information');
      process.exit(1);
    }
  }
  
  return { logsPerSecond, repeat };
}

// Main execution function
async function main() {
  // Parse command line arguments
  const { logsPerSecond, repeat } = parseArgs();
  
  // Configuration
  const parsedLogsDir = './1-logs-parsed';
  const outputLogsDir = '../1-logs-storage';
  const filenames = ['hpcmlog.json', 'monitoring_service.json', 'syslog.json'];
  
  // Create simulator instance
  const simulator = new LogsGenerationSimulator(parsedLogsDir, outputLogsDir, filenames, repeat);
  
  try {
    // Check if parsed logs directory exists
    try {
      await fs.promises.access(parsedLogsDir, fs.constants.R_OK);
    } catch (error) {
      console.error(`Error: Parsed logs directory '${parsedLogsDir}' does not exist or is not readable.`);
      console.error('Please run logs-parser.ts first to generate parsed logs.');
      process.exit(1);
    }
    
    // Check if all parsed log files exist
    let allExist = true;
    for (const filename of filenames) {
      const filePath = path.join(parsedLogsDir, filename);
      try {
        await fs.promises.access(filePath, fs.constants.R_OK);
        console.log(`✓ Found: ${filename}`);
      } catch (error) {
        console.error(`✗ Missing: ${filename}`);
        allExist = false;
      }
    }
    
    if (!allExist) {
      console.error('Cannot proceed: Some parsed log files are missing.');
      process.exit(1);
    }
    
    console.log('---');
    
    // Clear existing log files before starting
    await simulator.clearLogFiles();
    
    // Run the simulation
    await simulator.simulateContinuousStreaming(logsPerSecond);
    
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

// Run the simulator if this file is executed directly
if (require.main === module) {
  main();
}

export { LogsGenerationSimulator, ParsedLogEntry, LogEntryWithTimestamp };