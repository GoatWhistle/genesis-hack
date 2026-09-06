import type { PageProps } from "~/layout/types";
import { MatchStage } from "./MatchStage";
import { AmountBoard } from "./AmountBoard";
import { VetoBench } from "./VetoBench";
import { LayersSection } from "./LayersSection";
import { TwinSection } from "./TwinSection";
import { HonestySection } from "./HonestySection";
import { RunSection } from "./RunSection";
import "./home.css";

const Home = ({ go }: PageProps) => (
  <>
    <MatchStage go={go} />
    <AmountBoard />
    <VetoBench />
    <LayersSection />
    <TwinSection />
    <HonestySection />
    <RunSection />
  </>
);

export default Home;
