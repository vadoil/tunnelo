package config

// Tunnelo: DNS и маршрутизация для России.
//
// Секции dns/route конфига sing-box строятся здесь, а не стандартным
// путём setDns/setRoutingOptions. Конфиг проверен реальным трафиком
// через sing-box 1.13 (youtube/google -> proxy, ya.ru/ozon/gosuslugi ->
// direct), менять правила без повторной проверки не нужно.
//
// Имена outbound'ов во входных данных ("proxy"/"direct") переведены в
// внутренние теги ядра ("select"/"direct §hide§") здесь, в одном месте.

import (
	"time"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
	mDNS "github.com/miekg/dns"
)

const tunneloDomesticDNSTag = "dns-domestic"
const tunneloDomesticDNS = "tcp://77.88.8.8" // Яндекс-DNS, российские домены

// Домены российских сервисов: точные суффиксы поверх общих TLD.
// Зеркало списка из проверенного серверного конфига.
var tunneloRUDomains = []string{
	"yandex.ru", "yandex.net", "yandex.com", "ya.ru", "yastatic.net", "mc.yandex.ru",
	"ozon.ru", "ozone.ru", "ozon.io", "ozonusercontent.com",
	"wildberries.ru", "wbbasket.ru", "wbstatic.net",
	"gosuslugi.ru", "nalog.gov.ru", "nalog.ru", "mos.ru", "pos.gosuslugi.ru",
	"sberbank.ru", "sber.ru", "sberbank.com", "sbrf.ru",
	"tinkoff.ru", "tbank.ru", "alfabank.ru", "vtb.ru", "gazprombank.ru",
	"raiffeisen.ru", "psbank.ru",
	"mail.ru", "vk.com", "vk.ru", "vkontakte.ru", "userapi.com", "vkuser.net",
	"avito.ru", "avito.st", "2gis.ru", "2gis.com",
	"rutube.ru", "kinopoisk.ru", "dzen.ru",
	"rambler.ru", "lenta.ru", "ria.ru", "rbc.ru", "kommersant.ru",
	"megafon.ru", "mts.ru", "beeline.ru", "tele2.ru", "rt.ru",
	"cdnvideo.ru", "cdn-tinkoff.ru", "ftc.ru", "hh.ru", "drom.ru", "auto.ru",
}

var tunneloRUTLDs = []string{".ru", ".su", ".рф", ".moscow", ".tatar"}

// Диапазоны Яндекса: страховка для случаев, когда имя резолвится мимо нас.
var tunneloYandexCIDRs = []string{
	"5.45.192.0/18", "5.255.192.0/18", "37.9.64.0/18", "77.88.0.0/18",
	"87.250.224.0/19", "93.158.128.0/18", "95.108.128.0/17",
	"178.154.128.0/17", "213.180.192.0/19",
}

// setTunneloDns строит секцию dns.
//
// Оба резолвера ходят по TCP, а не по UDP. Российские провайдеры режут
// UDP/53 к внешним резолверам (проверено: запрос к 8.8.8.8 по UDP уходит
// в пустоту, TCP/53 открыт), а UDP внутри туннеля ненадёжен. На UDP
// не резолвилось ничего: ни YouTube с Instagram через туннель, ни поиск.
//
// dns-remote — 8.8.8.8 через туннель (внутри hysteria2 трафик уже зашифрован,
// поэтому TLS поверх не нужен); dns-domestic (Яндекс) напрямую — detour у
// него намеренно пустой: detour на empty direct outbound ядро отвергает.
func setTunneloDns(options *option.Options) error {
	remoteDNS, err := getDNSServerOptions(DNSRemoteTag, "tcp://8.8.8.8", "", OutboundMainDetour)
	if err != nil {
		return err
	}
	domesticDNS, err := getDNSServerOptions(tunneloDomesticDNSTag, tunneloDomesticDNS, "", "")
	if err != nil {
		return err
	}
	localDNS, err := getDNSServerOptions(DNSLocalTag, "local", "", "")
	if err != nil {
		return err
	}

	options.DNS = &option.DNSOptions{
		RawDNSOptions: option.RawDNSOptions{
			Servers: []option.DNSServerOptions{*remoteDNS, *domesticDNS, *localDNS},
			Rules:   tunneloDnsRules(),
			Final:   DNSRemoteTag,
			DNSClientOptions: option.DNSClientOptions{
				IndependentCache: true,
				Strategy:         option.DomainStrategy(C.DomainStrategyPreferIPv4),
			},
			ReverseMapping: true,
		},
	}
	return nil
}

// tunneloDnsRules — порядок правил важен, побеждает первое совпадение:
//  1. ip_accept_any -> dns-remote: если адрес уже известен (кэш или
//     reverse-mapping), не ходить в domestic повторно;
//  2. российские TLD и домены сервисов -> dns-domestic;
//  3. HTTPS/SVCB -> reject: ECH-записи ломают раздельную маршрутизацию
//     (побочка: часть сайтов теряет HTTP/3; первый кандидат на отключение).
func tunneloDnsRules() []option.DNSRule {
	rules := []option.DNSRule{}

		rules = append(rules, option.DNSRule{
		Type: C.RuleTypeDefault,
		DefaultOptions: option.DefaultDNSRule{
			RawDefaultDNSRule: option.RawDefaultDNSRule{
				DomainSuffix: append(append([]string{}, tunneloRUTLDs...), tunneloRUDomains...),
			},
			DNSRuleAction: option.DNSRuleAction{
				Action:       C.RuleActionTypeRoute,
				RouteOptions: option.DNSRouteActionOptions{Server: tunneloDomesticDNSTag},
			},
		},
	})

	rules = append(rules, option.DNSRule{
		Type: C.RuleTypeDefault,
		DefaultOptions: option.DefaultDNSRule{
			RawDefaultDNSRule: option.RawDefaultDNSRule{
				QueryType: []option.DNSQueryType{
					option.DNSQueryType(mDNS.StringToType["HTTPS"]),
					option.DNSQueryType(mDNS.StringToType["SVCB"]),
				},
			},
			DNSRuleAction: option.DNSRuleAction{
				Action:        C.RuleActionTypeReject,
				RejectOptions: option.RejectActionOptions{Method: C.RuleActionRejectMethodDefault},
			},
		},
	})

	return rules
}

// setTunneloRoute строит секцию route: sniff, hijack DNS, локалка и
// российские домены/CIDRs напрямую, финал - через выбранный прокси.
// default_domain_resolver обязателен с sing-box 1.12: им резолвится
// домен самого узла (dns-local), иначе курица-яйцо с подъёмом туннеля.
func setTunneloRoute(options *option.Options, hopt *HiddifyOptions) {
	rulesets := []option.RuleSet{}
	var adsRules []option.Rule
	if hopt.BlockAds {
		rulesets = append(rulesets, option.RuleSet{
			Type:   C.RuleSetTypeRemote,
			Tag:    "geosite-ads",
			Format: C.RuleSetFormatBinary,
			RemoteOptions: option.RemoteRuleSet{
				URL:            "https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/block/geosite-category-ads-all.srs",
				UpdateInterval: badoption.Duration(5 * time.Hour * 24),
				DownloadDetour: OutboundSelectTag,
			},
		})
		adsRules = append(adsRules, option.Rule{
			Type: C.RuleTypeDefault,
			DefaultOptions: option.DefaultRule{
				RawDefaultRule: option.RawDefaultRule{RuleSet: []string{"geosite-ads"}},
				RuleAction: option.RuleAction{
					Action:        C.RuleActionTypeReject,
					RejectOptions: option.RejectActionOptions{Method: C.RuleActionRejectMethodDefault},
				},
			},
		})
	}

	routeRules := []option.Rule{
		{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RuleAction: option.RuleAction{Action: C.RuleActionTypeSniff},
		}},
		{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{Protocol: []string{C.ProtocolDNS}},
			RuleAction:     option.RuleAction{Action: C.RuleActionTypeHijackDNS},
		}},
	}
	routeRules = append(routeRules, adsRules...)
	routeRules = append(routeRules,
		option.Rule{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{IPIsPrivate: true},
			RuleAction: option.RuleAction{
				Action:       C.RuleActionTypeRoute,
				RouteOptions: option.RouteActionOptions{Outbound: OutboundDirectTag},
			},
		}},
		tunneloDirectSuffixRule(tunneloRUTLDs),
		tunneloDirectSuffixRule(tunneloRUDomains),
		option.Rule{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{IPCIDR: tunneloYandexCIDRs},
			RuleAction: option.RuleAction{
				Action:       C.RuleActionTypeRoute,
				RouteOptions: option.RouteActionOptions{Outbound: OutboundDirectTag},
			},
		}},
		// QUIC в туннель не пускаем. YouTube и Instagram сначала пробуют
		// HTTP/3 поверх UDP; через туннель он идёт рвано — видео замирает,
		// лента не грузится. Отказ на UDP/443 заставляет их мгновенно
		// вернуться на обычный TCP, который работает стабильно.
		// Российские домены сюда не попадают: они ушли направо выше.
		option.Rule{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{
				Network: []string{"udp"},
				Port:    []uint16{443},
			},
			RuleAction: option.RuleAction{
				Action:        C.RuleActionTypeReject,
				RejectOptions: option.RejectActionOptions{Method: C.RuleActionRejectMethodDefault},
			},
		}},
	)

	options.Route = &option.RouteOptions{
		Rules:               routeRules,
		Final:               OutboundMainDetour,
		AutoDetectInterface: (!C.IsAndroid && !C.IsIos) && (hopt.EnableTun || hopt.EnableTunService),
		DefaultDomainResolver: &option.DomainResolveOptions{
			Server: DNSLocalTag,
		},
		RuleSet:     rulesets,
		FindProcess: false,
	}
}

func tunneloDirectSuffixRule(suffixes []string) option.Rule {
	return option.Rule{
		Type: C.RuleTypeDefault,
		DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{DomainSuffix: suffixes},
			RuleAction: option.RuleAction{
				Action:       C.RuleActionTypeRoute,
				RouteOptions: option.RouteActionOptions{Outbound: OutboundDirectTag},
			},
		},
	}
}
