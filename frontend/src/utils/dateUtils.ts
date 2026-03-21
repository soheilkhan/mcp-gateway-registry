import { formatDistanceToNow, parseISO, isValid } from 'date-fns';

/**
 * Format a date string or Date object as relative time (e.g., "2 hours ago", "3 days ago").
 *
 * @param date - ISO 8601 date string or Date object
 * @returns Formatted relative time string, or "Unknown" if invalid
 */
export function formatRelativeTime(date: string | Date | null | undefined): string {
  if (!date) {
    return 'Unknown';
  }

  try {
    const dateObj = typeof date === 'string' ? parseISO(date) : date;

    if (!isValid(dateObj)) {
      return 'Unknown';
    }

    return formatDistanceToNow(dateObj, { addSuffix: true });
  } catch (error) {
    console.error('Error formatting relative time:', error);
    return 'Unknown';
  }
}

/**
 * Format a date string or Date object as absolute date (e.g., "Jan 15, 2025, 3:30 PM").
 *
 * @param date - ISO 8601 date string or Date object
 * @returns Formatted absolute date string, or "Unknown" if invalid
 */
export function formatAbsoluteDate(date: string | Date | null | undefined): string {
  if (!date) {
    return 'Unknown';
  }

  try {
    const dateObj = typeof date === 'string' ? parseISO(date) : date;

    if (!isValid(dateObj)) {
      return 'Unknown';
    }

    return new Intl.DateTimeFormat('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }).format(dateObj);
  } catch (error) {
    console.error('Error formatting absolute date:', error);
    return 'Unknown';
  }
}

/**
 * Format a date with both relative and absolute time for tooltips.
 *
 * @param date - ISO 8601 date string or Date object
 * @returns Object with relative and absolute formatted dates
 */
export function formatDateWithTooltip(date: string | Date | null | undefined): {
  relative: string;
  absolute: string;
} {
  return {
    relative: formatRelativeTime(date),
    absolute: formatAbsoluteDate(date),
  };
}
