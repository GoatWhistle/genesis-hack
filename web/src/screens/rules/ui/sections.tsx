import { baseRules } from "~/shared/model/base";
import { ArchetypeBlock } from "./Archetypes";
import { RuleCheck } from "./RuleCheck";
import { AllFieldPatterns, AmountUnits, ErrorSemantics, StatusGroups } from "./Dictionaries";
import { ContractBridge, ContractStatuses } from "./Contracts";
import { Templates } from "./Templates";
import { Sandbox } from "./Sandbox";
export { ContractUpload } from "./ContractUpload";

export const Check = () => (
  <>
    <p className="prose-column rls-lead">
      Введите имя операции чужого API — счёт посчитается прямо здесь, по тем же регуляркам и
      весам, что и в сервисе. <code className="mono side-provider">cancelPayout</code> — самый
      показательный случай: это POST со словом <span className="mono">payout</span> в имени, и без
      veto он выиграл бы архетип создания.
    </p>
    <RuleCheck />
  </>
);

export const Archetypes = () => {
  const base = baseRules();

  return (
    <>
      <p className="prose-column rls-lead">
        Правило — это поле операции, регулярка по нему и вес. Веса нужны, чтобы слабый признак
        (<span className="mono">POST</span>) не перевешивал сильный — глагол в начале
        <span className="mono"> operationId</span>. Veto действует поверх весов и снимает кандидата
        целиком.
      </p>
      <div className="rls-archetypes">
        {base.archetypes.map((archetype) => (
          <ArchetypeBlock key={archetype.name} archetype={archetype} />
        ))}
      </div>
    </>
  );
};

export const Dictionaries = () => {
  const base = baseRules();

  return (
    <>
      <p className="prose-column rls-lead">
        Кроме архетипов <code className="mono">base.yml</code> держит четыре словаря: чем провайдер
        называет состояние, что значит код ошибки, как читается имя поля и в каких единицах указана
        сумма.
      </p>

      <div className="rls-sub">
        <h3 className="rls-h3">Группы состояний</h3>
        <p className="prose-column rls-note">
          Имена групп внутренние: контракт переводит их в свои статусы. Сравнение
          регистронезависимое — Nordbank пишет состояния капсом, остальные строчными.
        </p>
        <StatusGroups base={base} />
      </div>

      <div className="rls-sub rls-two">
        <div>
          <h3 className="rls-h3">Смысл ошибки</h3>
          <p className="rls-note">
            HTTP-код ответа → смысл. Что с этим смыслом делать, решает контракт: один откажет
            операции, другой поднимет исключение.
          </p>
          <ErrorSemantics base={base} />
        </div>
        <div>
          <h3 className="rls-h3">Единицы суммы</h3>
          <AmountUnits base={base} />
        </div>
      </div>

      <div className="rls-sub">
        <h3 className="rls-h3">Паттерны полей</h3>
        <p className="prose-column rls-note">
          Порядок важен: берётся первое правило, чья регулярка совпала с именем свойства.
        </p>
        <AllFieldPatterns base={base} />
      </div>
    </>
  );
};

export const Contracts = () => (
  <>
    <p className="prose-column rls-lead">
      <span className="mono side-contract">space_payments</span> и{" "}
      <span className="mono side-contract">plain_client</span> ссылаются на те же архетипы из{" "}
      <code className="mono">base.yml</code>, но называют роли по-своему, переводят состояния в свои
      статусы и печатают свой код.
    </p>
    <ContractBridge />

    <div className="rls-sub">
      <h3 className="rls-h3">Каждый переводит состояния в своё</h3>
      <ContractStatuses />
    </div>

    <div className="rls-sub">
      <h3 className="rls-h3">Шаблоны</h3>
      <p className="prose-column rls-note">
        Код заказчика не зашит в инструмент — он лежит в <code className="mono">.erb</code> рядом с
        контрактом и заполняется тем, что дал разбор.
      </p>
      <Templates />
    </div>
  </>
);

export const Playground = () => (
  <>
    <p className="prose-column rls-lead">
      Поменяйте вес или регулярку — и посмотрите, как поменялась бы раздача ролей на четырёх
      настоящих описаниях. Считается здесь же, никуда не сохраняется.
    </p>
    <Sandbox />
  </>
);
