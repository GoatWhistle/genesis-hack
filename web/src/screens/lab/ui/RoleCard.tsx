import { motion } from "motion/react";
import { isBound, type Role } from "~/shared/api/types";
import { roleMeta, roleTitle } from "~/shared/api/runs";
import { useSourceHandlers } from "./useProvenance";

interface RoleCardProps {
  contract: string;
  name: string;
  role: Role;
  order: number;
}

const Score = ({ score, threshold, order }: { score: number; threshold: number; order: number }) => {
  const scale = Math.max(score, threshold) * 1.15 || 1;
  const passed = score >= threshold;

  return (
    <div className="lab-score">
      <div
        className="lab-score-track"
        role="img"
        aria-label={`счёт ${score} при пороге ${threshold}`}
      >
        <motion.div
          className={`lab-score-bar${passed ? "" : " lab-score-bar-short"}`}
          initial={{ scaleX: 0 }}
          animate={{ scaleX: 1 }}
          transition={{ duration: 0.55, delay: 0.12 + order * 0.14, ease: [0.16, 1, 0.3, 1] }}
          style={{ width: `${(score / scale) * 100}%` }}
        />
        <span className="lab-score-threshold" style={{ left: `${(threshold / scale) * 100}%` }} />
      </div>
      <div className="lab-score-legend">
        <span>счёт {score}</span>
        <span>порог {threshold}</span>
      </div>
    </div>
  );
};

const bestOf = (why: string) => {
  const found = /лучший кандидат\s+(\S+)\s+набрал\s+(\d+)\s+при\s+пороге\s+(\d+)/.exec(why);
  if (!found) return undefined;
  return { operation: found[1], score: Number(found[2]), threshold: Number(found[3]) };
};

export const RoleCard = ({ contract, name, role, order }: RoleCardProps) => {
  const meta = roleMeta(contract, name);
  const trace = useSourceHandlers(`role:${name}`);
  const bound = isBound(role);
  const best = bound ? undefined : bestOf(role.why);
  const threshold = bound ? role.threshold : (best?.threshold ?? meta?.threshold ?? 0);

  return (
    <motion.article
      className={`panel lab-role${bound ? "" : " lab-role-stub"}${trace.lit ? " lab-linked" : ""}${trace.known ? " lab-linkable" : ""}`}
      {...trace.props}
      initial={{ opacity: 0.4, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay: order * 0.14, ease: [0.16, 1, 0.3, 1] }}
    >
      <div className="lab-role-head">
        <span className="lab-role-name">{roleTitle(contract, name)}</span>
        <span className="lab-role-key mono">{name}</span>
        {meta?.required ? <span className="chip chip-quiet">обязательна</span> : null}
        {trace.known ? <span className="lab-linkmark">{trace.label}</span> : null}
      </div>

      {bound ? (
        <>
          <div className="lab-role-head lab-role-head-next">
            <span className="chip chip-provider">{role.operation}</span>
            <span className="mono side-provider">{role.endpoint}</span>
          </div>
          <Score score={role.score} threshold={role.threshold} order={order} />
          <ul className="lab-rules">
            {role.matched_rules.map((rule) => (
              <li key={rule} className="lab-rule">
                <span className="lab-rule-mark" aria-hidden="true">
                  +
                </span>
                <span>{rule}</span>
              </li>
            ))}
          </ul>
        </>
      ) : (
        <>
          <div className="lab-role-head lab-role-head-next">
            {best ? (
              <span className="chip chip-quiet">
                <s>{best.operation}</s>
              </span>
            ) : (
              <span className="chip chip-quiet">
                <s>кандидатов нет</s>
              </span>
            )}
            <span className="label">роль осталась заглушкой</span>
          </div>
          <Score score={best?.score ?? 0} threshold={threshold} order={order} />
          <p className="notice lab-role-why">
            <span className="notice-mark" aria-hidden="true">
              !
            </span>
            {role.why}
          </p>
        </>
      )}
    </motion.article>
  );
};
