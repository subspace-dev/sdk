export enum LogLevel {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
    OFF = 4
}

export class Logger {
    private static instance: Logger;
    private logLevel: LogLevel = LogLevel.INFO;
    private prefix: string = '[Subspace SDK]';
    private isFirstLog: boolean = true;

    private constructor() {
        // Set log level from environment or default
        const envLogLevel = process.env.SUBSPACE_LOG_LEVEL || 'INFO';
        this.logLevel = LogLevel[envLogLevel.toUpperCase() as keyof typeof LogLevel] || LogLevel.INFO;
    }

    static getInstance(): Logger {
        if (!Logger.instance) {
            Logger.instance = new Logger();
        }
        return Logger.instance;
    }

    private showSDKHeader(): void {
        if (this.isFirstLog) {
            console.log('%c┌─────────────────────────────────────────────┐', 'color: #2196F3;');
            console.log('%c│           🚀 SUBSPACE SDK LOGS 🚀           │', 'color: #2196F3; font-weight: bold;');
            console.log('%c└─────────────────────────────────────────────┘', 'color: #2196F3;');
            console.log('');
            this.isFirstLog = false;
        }
    }

    setLogLevel(level: LogLevel): void {
        this.logLevel = level;
    }

    private shouldLog(level: LogLevel): boolean {
        return level >= this.logLevel;
    }

    private formatMessage(level: string, component: string, message: string, data?: any): string {
        const timestamp = new Date().toISOString();
        const baseMessage = `${this.prefix} ${timestamp} [${level}] [${component}] ${message}`;

        if (data) {
            return `${baseMessage} ${JSON.stringify(data, null, 2)}`;
        }
        return baseMessage;
    }

    debug(component: string, message: string, data?: any): void {
        if (this.shouldLog(LogLevel.DEBUG)) {
            console.debug(this.formatMessage('DEBUG', component, message, data));
        }
    }

    info(component: string, message: string, data?: any): void {
        if (this.shouldLog(LogLevel.INFO)) {
            console.info(this.formatMessage('INFO', component, message, data));
        }
    }

    warn(component: string, message: string, data?: any): void {
        if (this.shouldLog(LogLevel.WARN)) {
            console.warn(this.formatMessage('WARN', component, message, data));
        }
    }

    error(component: string, message: string, error?: any): void {
        if (this.shouldLog(LogLevel.ERROR)) {
            let errorData = error;
            if (error instanceof Error) {
                errorData = {
                    name: error.name,
                    message: error.message,
                    stack: error.stack
                };
            }
            logger.error(component, this.formatMessage('ERROR', component, message, errorData));
        }
    }

    // Operation-specific logging methods
    operationStart(component: string, operation: string, params?: any): void {
        this.info(component, `Starting ${operation}`, params);
    }

    operationSuccess(component: string, operation: string, result?: any, duration?: number): void {
        const message = duration ? `${operation} completed in ${duration}ms` : `${operation} completed successfully`;
        this.info(component, message, result);
    }

    operationError(component: string, operation: string, error: any, duration?: number): void {
        const message = duration ? `${operation} failed after ${duration}ms` : `${operation} failed`;
        this.error(component, message, error);
    }

    // Request/Response logging
    requestSent(component: string, method: string, processId: string, tags?: any): void {
        this.debug(component, `${method} request sent`, {
            processId,
            tags
        });
    }

    responseReceived(component: string, method: string, processId: string, success: boolean, data?: any): void {
        const status = success ? 'SUCCESS' : 'FAILURE';
        this.debug(component, `${method} response received [${status}]`, {
            processId,
            data: success ? data : undefined,
            error: !success ? data : undefined
        });
    }

    // Performance logging
    performance(component: string, operation: string, duration: number, details?: any): void {
        this.debug(component, `Performance: ${operation} took ${duration}ms`, details);
    }

    // State changes
    stateChange(component: string, change: string, oldValue?: any, newValue?: any): void {
        this.debug(component, `State change: ${change}`, {
            from: oldValue,
            to: newValue
        });
    }

    // Concise action logging for SDK operations
    actionStart(action: string, input?: any): void {
        this.showSDKHeader();

        // Start a collapsed group for the action
        console.groupCollapsed(
            `%c🚀 ${action}`,
            'color: #2196F3; font-weight: bold; font-size: 12px;'
        );

        if (input && Object.keys(input).length > 0) {
            console.log('%cInput:', 'color: #4CAF50; font-weight: bold;', input);
        }

        console.groupEnd();
    }

    actionResult(action: string, output?: any, success: boolean = true, duration?: number): void {
        const statusIcon = success ? '✅' : '❌';
        const statusText = success ? 'SUCCESS' : 'FAILED';
        const statusColor = success ? '#4CAF50' : '#F44336';
        const durationText = duration ? `${duration}ms` : '';

        // Start a collapsed group for the result
        console.groupCollapsed(
            `%c${statusIcon} ${action} result%c [${statusText}]%c ${durationText}`,
            `color: ${statusColor}; font-weight: bold; font-size: 12px;`,
            `color: ${statusColor}; font-size: 11px;`,
            'color: #666; font-size: 10px; font-style: italic;'
        );

        if (output !== undefined && output !== null) {
            const outputLabel = success ? 'Result:' : 'Error Details:';
            const outputColor = success ? '#2196F3' : '#F44336';
            console.log(`%c${outputLabel}`, `color: ${outputColor}; font-weight: bold;`, output);
        }

        console.groupEnd();
    }

    actionError(action: string, error: any, duration?: number): void {
        const errorStr = error instanceof Error ? error.message : String(error);
        const durationText = duration ? `${duration}ms` : '';

        // Start a collapsed group for the error
        console.groupCollapsed(
            `%c❌ ${action} result%c [FAILED]%c ${durationText}`,
            'color: #F44336; font-weight: bold; font-size: 12px;',
            'color: #F44336; font-size: 11px;',
            'color: #666; font-size: 10px; font-style: italic;'
        );

        console.log('%cError:', 'color: #F44336; font-weight: bold;', errorStr);

        if (error instanceof Error && error.stack) {
            console.log('%cStack Trace:', 'color: #FF9800; font-weight: bold;');
            console.log(error.stack);
        }

        console.groupEnd();
    }
}

// Export singleton instance
export const logger = Logger.getInstance();

// Helper function to measure execution time
export function measureTime<T>(fn: () => Promise<T>): Promise<{ result: T; duration: number }> {
    const start = Date.now();
    return fn().then(result => ({
        result,
        duration: Date.now() - start
    }));
}

// Helper function to wrap operations with action logging
export async function loggedAction<T>(
    action: string,
    input: any,
    operation: () => Promise<T>
): Promise<T> {
    const logger = Logger.getInstance();
    const startTime = Date.now();

    // Show action start
    logger.actionStart(action, input);

    try {
        const result = await operation();
        const duration = Date.now() - startTime;
        logger.actionResult(action, result, true, duration);
        return result;
    } catch (error) {
        const duration = Date.now() - startTime;
        logger.actionError(action, error, duration);
        throw error;
    }
}

// Decorator for automatic operation logging
export function logOperation(component: string, operation: string) {
    return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
        const originalMethod = descriptor.value;

        descriptor.value = async function (...args: any[]) {
            const start = Date.now();
            logger.operationStart(component, operation, args);

            try {
                const result = await originalMethod.apply(this, args);
                const duration = Date.now() - start;
                logger.operationSuccess(component, operation, result, duration);
                return result;
            } catch (error) {
                const duration = Date.now() - start;
                logger.operationError(component, operation, error, duration);
                throw error;
            }
        };

        return descriptor;
    };
} 