interface Props {
  size?: number;
}

export const PlayIcon = ({ size = 18 }: Props) => (
  <svg
    className="play-icon"
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
    <path d="M4.5 3.25v9.5l7.5-4.75z" />
  </svg>
);
