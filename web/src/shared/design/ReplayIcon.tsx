interface Props {
  size?: number;
}

export const ReplayIcon = ({ size = 15 }: Props) => (
  <svg
    className="replay-icon"
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
    <path d="M13.25 8a5.25 5.25 0 1 1-1.6-3.78" />
    <path d="M13.4 2.4v3.1h-3.1" />
  </svg>
);
