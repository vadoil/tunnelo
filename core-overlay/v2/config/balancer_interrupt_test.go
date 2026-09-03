package config

import (
	"testing"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/experimental/libbox"
	"github.com/sagernet/sing-box/option"
)

// Смена быстрейшего узла не должна рвать живые соединения.
//
// Балансировщик выбирает минимальную задержку без запаса, а узлы стоят
// рядом и различаются на миллисекунду — победитель меняется почти каждый
// замер. Пока стоял InterruptExistConnections, каждая такая смена закрывала
// все соединения разом, и человек терял связь на ровном месте.
func TestBalancerDoesNotDropLiveConnections(t *testing.T) {
	const nodes = `{"outbounds":[
		{"type":"hysteria2","tag":"Финляндия-1","server":"127.0.0.1","server_port":443,"password":"x"},
		{"type":"hysteria2","tag":"Финляндия-2","server":"127.0.0.2","server_port":443,"password":"x"}
	]}`

	opts, err := BuildConfig(
		libbox.BaseContext(nil),
		DefaultHiddifyOptions(),
		&ReadOptions{Content: nodes},
	)
	if err != nil {
		t.Fatalf("конфиг не собрался: %v", err)
	}

	balancers := 0
	for _, out := range opts.Outbounds {
		if out.Type != C.TypeBalancer {
			continue
		}
		balancers++
		o, ok := out.Options.(*option.BalancerOutboundOptions)
		if !ok {
			t.Fatalf("%s: неожиданный тип настроек %T", out.Tag, out.Options)
		}
		if o.InterruptExistConnections {
			t.Errorf("%s рвёт живые соединения при смене узла", out.Tag)
		}
	}
	if balancers == 0 {
		t.Fatal("балансировщиков в конфиге нет — тест ничего не проверил")
	}
}
