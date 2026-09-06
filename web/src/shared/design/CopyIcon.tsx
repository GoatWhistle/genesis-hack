interface Props {
  size?: number;
  done?: boolean;
}

export const CopyIcon = ({ size = 15, done = false }: Props) => (
  <svg
    className="copy-icon"
    width={size}
    height={size}
    viewBox="0 0 16 16"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.5"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    {done ? (
      <path d="M3 8.5 6.5 12 13 4.5" />
    ) : (
      <>
        <rect x="5.75" y="5.75" width="7.5" height="7.5" rx="1.5" />
        <path d="M10.25 5.75V4.25a1.5 1.5 0 0 0-1.5-1.5h-4.5a1.5 1.5 0 0 0-1.5 1.5v4.5a1.5 1.5 0 0 0 1.5 1.5h1.5" />
      </>
    )}
  </svg>
);
