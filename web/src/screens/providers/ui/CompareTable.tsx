import type { Cell, CompareRow } from "../model/compare";

const CellView = ({ cell }: { cell: Cell }) => (
  <>
    <span className={cell.side === "provider" ? "side-provider" : cell.side === "contract" ? "side-contract" : ""}>
      {cell.text}
    </span>
    {cell.note ? <span className="cmp-note">{cell.note}</span> : null}
  </>
);

interface Props {
  providers: string[];
  rows: CompareRow[];
  active: string | undefined;
  onPick: (provider: string) => void;
}

export const CompareTable = ({ providers, rows, active, onPick }: Props) => (
  <div className="scroll-x cmp-wrap">
    <table className="cmp">
      <caption className="sr-only">Сравнение четырёх описаний по шести признакам</caption>
      <thead>
        <tr>
          <th scope="col" className="cmp-corner">
            <span className="label">признак</span>
          </th>
          {providers.map((provider) => (
            <th key={provider} scope="col" data-active={provider === active}>
              <button type="button" className="cmp-head" onClick={() => onPick(provider)}>
                {provider}
              </button>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.key}>
            <th scope="row">
              <span className="cmp-title">{row.title}</span>
              <span className="cmp-hint">{row.hint}</span>
            </th>
            {providers.map((provider) => {
              const cell = row.cells[provider];
              return (
                <td key={provider} data-active={provider === active} data-odd={cell?.odd ?? false}>
                  {cell ? <CellView cell={cell} /> : null}
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);
