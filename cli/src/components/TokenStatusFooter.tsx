import {Box, Text} from "ink";

interface TokenStatusFooterProps {
  secondsRemaining?: number;
  expired: boolean;
  isRefreshing: boolean;
  lastRefresh?: Date;
  source?: string;
  model?: string;
}

export function TokenStatusFooter({
  secondsRemaining,
  expired,
  isRefreshing,
  lastRefresh,
  source,
  model
}: TokenStatusFooterProps) {
  const formatTime = (seconds: number): string => {
    if (seconds < 0) return "expired";
    if (seconds < 60) return `${seconds}s`;
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}m ${secs}s`;
  };

  const getStatusIcon = (): string => {
    if (isRefreshing) return "🔄";
    if (expired || (secondsRemaining !== undefined && secondsRemaining <= 0)) return "❌";
    if (secondsRemaining !== undefined && secondsRemaining < 60) return "⚠️";
    return "🔑";
  };

  const getStatusText = (): string => {
    if (isRefreshing) return "Refreshing...";
    if (expired || (secondsRemaining !== undefined && secondsRemaining <= 0)) return "Expired";
    if (secondsRemaining !== undefined) return `Valid for ${formatTime(secondsRemaining)}`;
    return "Unknown";
  };

  const getStatusColor = (): string => {
    if (isRefreshing) return "cyan";
    if (expired || (secondsRemaining !== undefined && secondsRemaining <= 0)) return "red";
    if (secondsRemaining !== undefined && secondsRemaining < 60) return "yellow";
    return "green";
  };

  const lastRefreshText = lastRefresh
    ? lastRefresh.toLocaleTimeString("en-US", {hour12: false})
    : "N/A";

  return (
    <Box flexDirection="row" gap={1}>
      <Text color={getStatusColor()}>
        {getStatusIcon()} Token: {getStatusText()}
      </Text>
      {source && (
        <Text color="gray" dimColor>
          | Source: {source}
        </Text>
      )}
      <Text color="gray" dimColor>
        | Last refresh: {lastRefreshText}
      </Text>
      {model && (
        <Text color="gray" dimColor>
          | Model: {model}
        </Text>
      )}
    </Box>
  );
}
