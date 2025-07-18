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