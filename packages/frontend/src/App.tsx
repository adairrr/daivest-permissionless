import Layout from "./components/Layout";
import { useAccount } from "wagmi";

function App() {
  const account = useAccount();

  return (
    <Layout>
      <div>
        <h2>Account</h2>
        <div>
          status: {account.status}
          <br />
          addresses: {JSON.stringify(account.addresses)}
          <br />
          chainId: {account.chainId}
        </div>
      </div>
    </Layout>
  );
}

export default App;
