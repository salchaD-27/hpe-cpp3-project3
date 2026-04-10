import * as fs from 'fs';
import * as path from 'path';

interface LogEntry {
  _index: string;
  _id: string;
  _score: number;
  _source: {
    Resource?: {
      [key: string]: any;
    };
    Body?: string;
    Severity?: string;
    SeverityText?: string;
    Attributes?: {
      [key: string]: any;
    };
    [key: string]: any;
  };
}

interface ParsedLogEntry {
  Resource: { [key: string]: any };
  Body: string;
  Severity: string;
  Attributes: { [key: string]: any };
}

class LogsParser {
  private inputDir: string;
  private outputDir: string;
  private filenames: string[];

  constructor(inputDir: string, outputDir: string, filenames: string[]) {
    this.inputDir = inputDir;
    this.outputDir = outputDir;
    this.filenames = filenames;
  }

  /**
   * Parse a single log file and save only the parsed logs
   */
  private async parseFile(filename: string): Promise<void> {
    const inputPath = path.join(this.inputDir, filename);
    const outputPath = path.join(this.outputDir, filename);

    console.log(`Processing: ${inputPath}`);

    try {
      // Read the input file
      const fileContent = await fs.promises.readFile(inputPath, 'utf-8');
      const jsonData = JSON.parse(fileContent);

      // Check if the file has the expected structure
      if (!jsonData.hits || !jsonData.hits.hits) {
        console.warn(`Warning: ${filename} does not have expected structure (hits.hits missing)`);
        return;
      }

      // Parse each log entry and collect only the parsed logs
      const parsedLogs = jsonData.hits.hits.map((entry: LogEntry) => {
        return this.parseLogEntry(entry);
      });

      // Ensure output directory exists
      await fs.promises.mkdir(this.outputDir, { recursive: true });

      // Write only the parsed logs array to output file
      await fs.promises.writeFile(
        outputPath,
        JSON.stringify(parsedLogs, null, 2),
        'utf-8'
      );

      console.log(`✓ Parsed ${parsedLogs.length} entries from ${filename} -> ${outputPath}`);
    } catch (error) {
      console.error(`Error processing ${filename}:`, error);
      throw error;
    }
  }

  /**
   * Parse a single log entry, extracting only desired fields
   */
  private parseLogEntry(entry: LogEntry): ParsedLogEntry {
    const source = entry._source;
    
    // Extract Resource object (default to empty object if not present)
    const resource = source.Resource || {};
    
    // Extract Body (default to empty string if not present)
    const body = source.Body || '';
    
    // Extract Severity: use Severity if present, otherwise SeverityText
    let severity = '';
    if (source.Severity) {
      severity = source.Severity;
    } else if (source.SeverityText) {
      severity = source.SeverityText;
    } else {
      severity = '';
    }
    
    // Extract Attributes (default to empty object if not present)
    const attributes = source.Attributes || {};
    
    return {
      Resource: resource,
      Body: body,
      Severity: severity,
      Attributes: attributes
    };
  }

  /**
   * Process all files in sequence
   */
  public async parseAll(): Promise<void> {
    console.log('Starting log parsing...');
    console.log(`Input directory: ${this.inputDir}`);
    console.log(`Output directory: ${this.outputDir}`);
    console.log(`Files to process: ${this.filenames.join(', ')}`);
    console.log('---');

    for (const filename of this.filenames) {
      await this.parseFile(filename);
    }

    console.log('---');
    console.log('✓ All files processed successfully!');
  }

  /**
   * Check if input files exist before processing
   */
  public async validateInputFiles(): Promise<boolean> {
    let allExist = true;
    
    for (const filename of this.filenames) {
      const filePath = path.join(this.inputDir, filename);
      try {
        await fs.promises.access(filePath, fs.constants.R_OK);
        console.log(`✓ Found: ${filename}`);
      } catch (error) {
        console.error(`✗ Missing or unreadable: ${filename}`);
        allExist = false;
      }
    }
    
    return allExist;
  }
}

// Main execution function
async function main() {
  // Configuration
  const inputDir = './0-logs-original'; // Current directory where JSON files are located
  const outputDir = './1-logs-parsed';
  const filenames = ['hpcmlog.json', 'monitoring_service.json', 'syslog.json'];

  // Create parser instance
  const parser = new LogsParser(inputDir, outputDir, filenames);

  try {
    // Validate input files
    console.log('Validating input files...');
    const filesExist = await parser.validateInputFiles();
    
    if (!filesExist) {
      console.error('Cannot proceed: Some input files are missing or unreadable.');
      process.exit(1);
    }
    
    console.log('---');
    
    // Parse all files
    await parser.parseAll();
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

// Run the parser if this file is executed directly
if (require.main === module) {
  main();
}

export { LogsParser, ParsedLogEntry };