# ADR-0002: MVP Access Protection and Environment Scope

- Status: Accepted
- Date: 2026-10-04

## Context

MVPではアプリケーション内のログイン処理とPrivate Endpointを実装しない。一方、`AGENTS.md`は認証なしの環境を一般公開しないことを求めている。App Serviceは既定で公開URLを持つため、何もしなければDev環境がインターネットへ公開され、Azure OpenAIを第三者に利用されるおそれがある。

また、CI/CDはProdへのapplyを定義していたが、MVPの完了条件はLocalとDevだけを対象としており、ProdがMVPの範囲に含まれるかが不明確だった。

## Decision

- Dev環境のApp ServiceはEasy Auth（Microsoft Entra IDプロバイダー）を有効にし、許可したアカウントだけがアクセスできるようにする。設定はTerraformで管理する。
- アプリケーションはEasy Authの認証情報を所有者識別子に使わず、MVPでは固定の開発者IDを使い続ける。
- ProdはTerraformの定義とplanまでをMVPの範囲とし、applyはMVP完了後に行う。

## Alternatives

- IP許可リスト: 設定は簡単だが、接続元IPが変わるたびに更新が必要になる。社内展開時にも再設計が必要になる。
- Easy AuthとIP許可リストの併用: 最も制限が強いが、MVPの検証用途に対して運用の手間が大きい。

## Consequences

Dev環境は、アプリケーションに認証処理を実装しなくても保護される。社内展開時は、Easy Authの許可対象を広げ、認証済みユーザーIDを所有者識別子として使う形へ段階的に移行できる。

Easy Auth用のEntra IDアプリ登録が必要になる。その管理方法は`docs/open-questions.md`で扱う。Prodの構築時期とアクセス制御は、MVP完了後に別途決定する。
