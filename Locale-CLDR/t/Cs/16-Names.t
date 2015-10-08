#!/usr/bin/perl
# Do not normalise this test file. It has deliberately unnormalised characters in it.
use v5.10;
use strict;
use warnings;
use utf8;
use if $^V ge v5.12.0, feature => 'unicode_strings';

use Test::More tests => 23;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new('cs_CZ');
my $other_locale = Locale::CLDR->new('en_US');

is($locale->locale_name(), 'čeština (Česká republika)', 'Locale name from current locale');
is($locale->locale_name('fr_CA'), 'francouzština (Kanada)', 'Locale name from string');
is($locale->locale_name($other_locale), 'angličtina (USA)', 'Locale name from other locale object');

is($locale->language_name(), 'čeština', 'Language name from current locale');
is($locale->language_name('fr'), 'francouzština', 'Language name from string');
is($locale->language_name($other_locale), 'angličtina', 'Language name from other locale object');

my $all_languages = {
	'aa' => 'afarština',
	'ab' => 'abcházština',
	'ace' => 'acehština',
	'ach' => 'akolština',
	'ada' => 'adangme',
	'ady' => 'adygejština',
	'ae' => 'avestánština',
	'aeb' => 'arabština (tuniská)',
	'af' => 'afrikánština',
	'afh' => 'afrihili',
	'agq' => 'aghem',
	'ain' => 'ainština',
	'ak' => 'akanština',
	'akk' => 'akkadština',
	'akz' => 'alabamština',
	'ale' => 'aleutština',
	'aln' => 'albánština (Gheg)',
	'alt' => 'altajština (jižní)',
	'am' => 'amharština',
	'an' => 'aragonština',
	'ang' => 'staroangličtina',
	'anp' => 'angika',
	'ar' => 'arabština',
	'ar_001' => 'arabština (moderní standardní)',
	'arc' => 'aramejština',
	'arn' => 'araukánština',
	'aro' => 'araonština',
	'arp' => 'arapažština',
	'arq' => 'arabština (alžírská)',
	'arw' => 'arawacké jazyky',
	'ary' => 'arabština (marocká)',
	'arz' => 'arabština (egyptská)',
	'as' => 'ásámština',
	'asa' => 'asu',
	'ase' => 'znaková řeč (americká)',
	'ast' => 'asturština',
	'av' => 'avarština',
	'avk' => 'kotava',
	'awa' => 'awadhština',
	'ay' => 'ajmarština',
	'az' => 'ázerbájdžánština',
	'az@alt=short' => 'ázerbájdžánština',
	'ba' => 'baškirština',
	'bal' => 'balúčština',
	'ban' => 'balijština',
	'bar' => 'bavorština',
	'bas' => 'basa',
	'bax' => 'bamun',
	'bbc' => 'batak toba',
	'bbj' => 'ghomala',
	'be' => 'běloruština',
	'bej' => 'bedža',
	'bem' => 'bembština',
	'bew' => 'batavština',
	'bez' => 'bena',
	'bfd' => 'bafut',
	'bfq' => 'badagština',
	'bg' => 'bulharština',
	'bgn' => 'balúčština (západní)',
	'bho' => 'bhojpurština',
	'bi' => 'bislamština',
	'bik' => 'bikolština',
	'bin' => 'bini',
	'bjn' => 'bandžarština',
	'bkm' => 'kom',
	'bla' => 'siksika',
	'bm' => 'bambarština',
	'bn' => 'bengálština',
	'bo' => 'tibetština',
	'bpy' => 'bišnuprijskomanipurština',
	'bqi' => 'bachtijárština',
	'br' => 'bretonština',
	'bra' => 'bradžština',
	'brh' => 'brahujština',
	'brx' => 'bodoština',
	'bs' => 'bosenština',
	'bss' => 'akoose',
	'bua' => 'burjatština',
	'bug' => 'bugiština',
	'bum' => 'bulu',
	'byn' => 'blinština',
	'byv' => 'medumba',
	'ca' => 'katalánština',
	'cad' => 'caddo',
	'car' => 'karibština',
	'cay' => 'kajugština',
	'cch' => 'atsam',
	'ce' => 'čečenština',
	'ceb' => 'cebuánština',
	'cgg' => 'kiga',
	'ch' => 'čamoro',
	'chb' => 'čibča',
	'chg' => 'čagatajština',
	'chk' => 'čukština',
	'chm' => 'marijština',
	'chn' => 'činuk pidžin',
	'cho' => 'čoktština',
	'chp' => 'čipevajština',
	'chr' => 'čerokézština',
	'chy' => 'čejenština',
	'ckb' => 'kurdština (sorání)',
	'co' => 'korsičtina',
	'cop' => 'koptština',
	'cps' => 'kapiznonština',
	'cr' => 'kríjština',
	'crh' => 'turečtina (krymská)',
	'cs' => 'čeština',
	'csb' => 'kašubština',
	'cu' => 'staroslověnština',
	'cv' => 'čuvaština',
	'cy' => 'velština',
	'da' => 'dánština',
	'dak' => 'dakotština',
	'dar' => 'dargština',
	'dav' => 'taita',
	'de' => 'němčina',
	'de_CH' => 'němčina standardní (Švýcarsko)',
	'del' => 'delawarština',
	'den' => 'slejvština (athabaský jazyk)',
	'dgr' => 'dogrib',
	'din' => 'dinkština',
	'dje' => 'zarmština',
	'doi' => 'dogarština',
	'dsb' => 'dolnolužická srbština',
	'dtp' => 'kadazandusunština',
	'dua' => 'dualština',
	'dum' => 'holandština (středověká)',
	'dv' => 'maledivština',
	'dyo' => 'jola-fonyi',
	'dyu' => 'djula',
	'dz' => 'dzongkä',
	'dzg' => 'dazaga',
	'ebu' => 'embu',
	'ee' => 'eweština',
	'efi' => 'efikština',
	'egl' => 'emilijština',
	'egy' => 'egyptština stará',
	'eka' => 'ekajuk',
	'el' => 'řečtina',
	'elx' => 'elamitština',
	'en' => 'angličtina',
	'en_GB@alt=short' => 'angličtina (VB)',
	'en_US' => 'angličtina (USA)',
	'en_US@alt=short' => 'angličtina (USA)',
	'enm' => 'angličtina (středověká)',
	'eo' => 'esperanto',
	'es' => 'španělština',
	'es_ES' => 'španělština (Evropa)',
	'esu' => 'jupikština (středoaljašská)',
	'et' => 'estonština',
	'eu' => 'baskičtina',
	'ewo' => 'ewondo',
	'ext' => 'extremadurština',
	'fa' => 'perština',
	'fan' => 'fang',
	'fat' => 'fantština',
	'ff' => 'fulbština',
	'fi' => 'finština',
	'fil' => 'filipínština',
	'fit' => 'finština (tornedalská)',
	'fj' => 'fidžijština',
	'fo' => 'faerština',
	'fon' => 'fonština',
	'fr' => 'francouzština',
	'frc' => 'francouzština (kajunská)',
	'frm' => 'francouzština (středověká)',
	'fro' => 'francouzština (stará)',
	'frp' => 'franko-provensálština',
	'frr' => 'fríština (severní)',
	'frs' => 'fríština (východní)',
	'fur' => 'furlanština',
	'fy' => 'fríština',
	'ga' => 'irština',
	'gaa' => 'gaština',
	'gag' => 'gagauzština',
	'gan' => 'čínština (dialekty Gan)',
	'gay' => 'gayo',
	'gba' => 'gbaja',
	'gbz' => 'daríjština (zoroastrijská)',
	'gd' => 'skotská gaelština',
	'gez' => 'geez',
	'gil' => 'kiribatština',
	'gl' => 'galicijština',
	'glk' => 'gilačtina',
	'gmh' => 'hornoněmčina (středověká)',
	'gn' => 'guaranština',
	'goh' => 'hornoněmčina (stará)',
	'gom' => 'konkánština (Goa)',
	'gon' => 'góndština',
	'gor' => 'gorontalo',
	'got' => 'gótština',
	'grb' => 'grebo',
	'grc' => 'starořečtina',
	'gsw' => 'němčina (Švýcarsko)',
	'gu' => 'gudžarátština',
	'guc' => 'wayúuština',
	'gur' => 'frafra',
	'guz' => 'gusii',
	'gv' => 'manština',
	'gwi' => 'gwichʼin',
	'ha' => 'hauština',
	'hai' => 'haidština',
	'hak' => 'čínština (dialekty Hakka)',
	'haw' => 'havajština',
	'he' => 'hebrejština',
	'hi' => 'hindština',
	'hif' => 'hindština (Fidži)',
	'hil' => 'hiligajnonština',
	'hit' => 'chetitština',
	'hmn' => 'hmongština',
	'ho' => 'hiri motu',
	'hr' => 'chorvatština',
	'hsb' => 'hornolužická srbština',
	'hsn' => 'čínština (dialekty Xiang)',
	'ht' => 'haitština',
	'hu' => 'maďarština',
	'hup' => 'hupa',
	'hy' => 'arménština',
	'hz' => 'hererština',
	'ia' => 'interlingua',
	'iba' => 'ibanština',
	'ibb' => 'ibibio',
	'id' => 'indonéština',
	'ie' => 'interlingue',
	'ig' => 'igboština',
	'ii' => 'iština (sečuánská)',
	'ik' => 'inupiakština',
	'ilo' => 'ilokánština',
	'inh' => 'inguština',
	'io' => 'ido',
	'is' => 'islandština',
	'it' => 'italština',
	'iu' => 'inuktitutština',
	'izh' => 'ingrijština',
	'ja' => 'japonština',
	'jam' => 'jamajská kreolština',
	'jbo' => 'lojban',
	'jgo' => 'ngomba',
	'jmc' => 'mašame',
	'jpr' => 'judeoperština',
	'jrb' => 'judeoarabština',
	'jut' => 'jutština',
	'jv' => 'javánština',
	'ka' => 'gruzínština',
	'kaa' => 'karakalpačtina',
	'kab' => 'kabylština',
	'kac' => 'kačijština',
	'kaj' => 'jju',
	'kam' => 'kambština',
	'kaw' => 'kawi',
	'kbd' => 'kabardinština',
	'kbl' => 'kanembu',
	'kcg' => 'tyap',
	'kde' => 'makonde',
	'kea' => 'kapverdština',
	'ken' => 'kenyang',
	'kfo' => 'koro',
	'kg' => 'konžština',
	'kgp' => 'kaingang',
	'kha' => 'khásí',
	'kho' => 'chotánština',
	'khq' => 'koyra chiini',
	'khw' => 'chovarština',
	'ki' => 'kikujština',
	'kiu' => 'zazakština',
	'kj' => 'kuaňamština',
	'kk' => 'kazaština',
	'kkj' => 'kako',
	'kl' => 'grónština',
	'kln' => 'kalendžin',
	'km' => 'khmérština',
	'kmb' => 'kimbundština',
	'kn' => 'kannadština',
	'ko' => 'korejština',
	'koi' => 'komi-permjačtina',
	'kok' => 'konkánština',
	'kos' => 'kosrajština',
	'kpe' => 'kpelle',
	'kr' => 'kanuri',
	'krc' => 'karačajevo-balkarština',
	'kri' => 'krio',
	'krj' => 'kinaraj-a',
	'krl' => 'karelština',
	'kru' => 'kuruchština',
	'ks' => 'kašmírština',
	'ksb' => 'šambala',
	'ksf' => 'bafia',
	'ksh' => 'kolínština',
	'ku' => 'kurdština',
	'kum' => 'kumyčtina',
	'kut' => 'kutenajština',
	'kv' => 'komijština',
	'kw' => 'kornština',
	'ky' => 'kyrgyzština',
	'la' => 'latina',
	'lad' => 'ladinština',
	'lag' => 'langi',
	'lah' => 'lahndština',
	'lam' => 'lambština',
	'lb' => 'lucemburština',
	'lez' => 'lezginština',
	'lfn' => 'lingua franca nova',
	'lg' => 'gandština',
	'li' => 'limburština',
	'lij' => 'ligurština',
	'liv' => 'livonština',
	'lkt' => 'lakotština',
	'lmo' => 'lombardština',
	'ln' => 'lingalština',
	'lo' => 'laoština',
	'lol' => 'mongština',
	'loz' => 'lozština',
	'lrc' => 'lúrština (severní)',
	'lt' => 'litevština',
	'ltg' => 'latgalština',
	'lu' => 'lubu-katanžština',
	'lua' => 'luba-luluaština',
	'lui' => 'luiseňo',
	'lun' => 'lundština',
	'luo' => 'luoština',
	'lus' => 'mizoština',
	'luy' => 'luhja',
	'lv' => 'lotyština',
	'lzh' => 'čínština (klasická)',
	'lzz' => 'lazština',
	'mad' => 'madurština',
	'maf' => 'mafa',
	'mag' => 'magahijština',
	'mai' => 'maithiliština',
	'mak' => 'makasarština',
	'man' => 'mandingština',
	'mas' => 'masajština',
	'mde' => 'maba',
	'mdf' => 'mokšanština',
	'mdr' => 'mandar',
	'men' => 'mende',
	'mer' => 'meru',
	'mfe' => 'mauricijská kreolština',
	'mg' => 'malgaština',
	'mga' => 'irština (středověká)',
	'mgh' => 'makhuwa-meetto',
	'mgo' => 'meta’',
	'mh' => 'maršálština',
	'mi' => 'maorština',
	'mic' => 'micmac',
	'min' => 'minangkabau',
	'mk' => 'makedonština',
	'ml' => 'malajálamština',
	'mn' => 'mongolština',
	'mnc' => 'mandžuština',
	'mni' => 'manipurština',
	'moh' => 'mohawkština',
	'mos' => 'mosi',
	'mr' => 'maráthština',
	'mrj' => 'marijština (západní)',
	'ms' => 'malajština',
	'mt' => 'maltština',
	'mua' => 'mundang',
	'mul' => 'složené (víceřádkové) jazyky',
	'mus' => 'kríkština',
	'mwl' => 'mirandština',
	'mwr' => 'márvárština',
	'mwv' => 'mentavajština',
	'my' => 'barmština',
	'mye' => 'myene',
	'myv' => 'erzjanština',
	'mzn' => 'mázandaránština',
	'na' => 'naurština',
	'nan' => 'čínština (dialekty Minnan)',
	'nap' => 'neapolština',
	'naq' => 'namaština',
	'nb' => 'norština (bokmål)',
	'nd' => 'ndebele (Zimbabwe)',
	'nds' => 'dolnoněmčina',
	'nds_NL' => 'dolnosaština',
	'ne' => 'nepálština',
	'new' => 'névárština',
	'ng' => 'ndondština',
	'nia' => 'nias',
	'niu' => 'niueština',
	'njo' => 'ao (jazyky Nágálandu)',
	'nl' => 'nizozemština',
	'nl_BE' => 'vlámština',
	'nmg' => 'kwasio',
	'nn' => 'norština (nynorsk)',
	'nnh' => 'ngiemboon',
	'no' => 'norština',
	'nog' => 'nogajština',
	'non' => 'norština historická',
	'nov' => 'novial',
	'nqo' => 'n’ko',
	'nr' => 'ndebele (Jižní Afrika)',
	'nso' => 'sotština (severní)',
	'nus' => 'nuerština',
	'nv' => 'navažština',
	'nwc' => 'newarština (klasická)',
	'ny' => 'ňandžština',
	'nym' => 'ňamwežština',
	'nyn' => 'ňankolština',
	'nyo' => 'ňorština',
	'nzi' => 'nzima',
	'oc' => 'okcitánština',
	'oj' => 'odžibvejština',
	'om' => 'oromština',
	'or' => 'urijština',
	'os' => 'osetština',
	'osa' => 'osage',
	'ota' => 'turečtina (osmanská)',
	'pa' => 'paňdžábština',
	'pag' => 'pangasinanština',
	'pal' => 'pahlavština',
	'pam' => 'papangau',
	'pap' => 'papiamento',
	'pau' => 'palauština',
	'pcd' => 'picardština',
	'pdc' => 'němčina (pensylvánská)',
	'pdt' => 'němčina (plautdietsch)',
	'peo' => 'staroperština',
	'pfl' => 'falčtina',
	'phn' => 'féničtina',
	'pi' => 'pálí',
	'pl' => 'polština',
	'pms' => 'piemonština',
	'pnt' => 'pontština',
	'pon' => 'pohnpeiština',
	'prg' => 'pruština',
	'pro' => 'provensálština',
	'ps' => 'paštština',
	'pt' => 'portugalština',
	'pt_PT' => 'portugalština (Evropa)',
	'qu' => 'kečuánština',
	'quc' => 'kičé',
	'qug' => 'kečuánština (chimborazo)',
	'raj' => 'rádžastánština',
	'rap' => 'rapanujština',
	'rar' => 'rarotongánština',
	'rgn' => 'romaňolština',
	'rif' => 'rífština',
	'rm' => 'rétorománština',
	'rn' => 'kirundština',
	'ro' => 'rumunština',
	'ro_MD' => 'moldavština',
	'rof' => 'rombo',
	'rom' => 'romština',
	'root' => 'kořen',
	'rtm' => 'rotumanština',
	'ru' => 'ruština',
	'rue' => 'rusínština',
	'rug' => 'rovianština',
	'rup' => 'arumunština',
	'rw' => 'kiňarwandština',
	'rwk' => 'rwa',
	'sa' => 'sanskrt',
	'sad' => 'sandawština',
	'sah' => 'jakutština',
	'sam' => 'samarština',
	'saq' => 'samburu',
	'sas' => 'sasakština',
	'sat' => 'santálština',
	'saz' => 'saurášterština',
	'sba' => 'ngambay',
	'sbp' => 'sangoština',
	'sc' => 'sardština',
	'scn' => 'sicilština',
	'sco' => 'skotština',
	'sd' => 'sindhština',
	'sdc' => 'sassarština',
	'sdh' => 'kurdština (jižní)',
	'se' => 'sámština (severní)',
	'see' => 'seneca',
	'seh' => 'sena',
	'sei' => 'seriština',
	'sel' => 'selkupština',
	'ses' => 'koyraboro senni',
	'sg' => 'sangština',
	'sga' => 'irština (stará)',
	'sgs' => 'žemaitština',
	'sh' => 'srbochorvatština',
	'shi' => 'tachelhit',
	'shn' => 'šanština',
	'shu' => 'arabština (čadská)',
	'si' => 'sinhálština',
	'sid' => 'sidamo',
	'sk' => 'slovenština',
	'sl' => 'slovinština',
	'sli' => 'němčina (slezská)',
	'sly' => 'selajarština',
	'sm' => 'samojština',
	'sma' => 'sámština (jižní)',
	'smj' => 'sámština (lulejská)',
	'smn' => 'sámština (inarijská)',
	'sms' => 'sámština (skoltská)',
	'sn' => 'šonština',
	'snk' => 'sonikština',
	'so' => 'somálština',
	'sog' => 'sogdština',
	'sq' => 'albánština',
	'sr' => 'srbština',
	'srn' => 'sranan tongo',
	'srr' => 'sererština',
	'ss' => 'siswatština',
	'ssy' => 'saho',
	'st' => 'sotština (jižní)',
	'stq' => 'fríština (saterlandská)',
	'su' => 'sundština',
	'suk' => 'sukuma',
	'sus' => 'susu',
	'sux' => 'sumerština',
	'sv' => 'švédština',
	'sw' => 'svahilština',
	'swb' => 'komorština',
	'swc' => 'svahilština (Kongo)',
	'syc' => 'syrština (klasická)',
	'syr' => 'syrština',
	'szl' => 'slezština',
	'ta' => 'tamilština',
	'tcy' => 'tuluština',
	'te' => 'telugština',
	'tem' => 'temne',
	'teo' => 'teso',
	'ter' => 'tereno',
	'tet' => 'tetumština',
	'tg' => 'tádžičtina',
	'th' => 'thajština',
	'ti' => 'tigrinijština',
	'tig' => 'tigrejština',
	'tiv' => 'tivština',
	'tk' => 'turkmenština',
	'tkl' => 'tokelauština',
	'tkr' => 'cachurština',
	'tl' => 'tagalog',
	'tlh' => 'klingonština',
	'tli' => 'tlingit',
	'tly' => 'talyština',
	'tmh' => 'tamašek',
	'tn' => 'setswanština',
	'to' => 'tongánština',
	'tog' => 'tonžština (nyasa)',
	'tpi' => 'tok pisin',
	'tr' => 'turečtina',
	'tru' => 'turojština',
	'trv' => 'taroko',
	'ts' => 'tsonga',
	'tsd' => 'tsakonština',
	'tsi' => 'tsimšijské jazyky',
	'tt' => 'tatarština',
	'ttt' => 'tatština',
	'tum' => 'tumbukština',
	'tvl' => 'tuvalština',
	'tw' => 'twi',
	'twq' => 'tasawaq',
	'ty' => 'tahitština',
	'tyv' => 'tuvinština',
	'tzm' => 'tamazight (střední Maroko)',
	'udm' => 'udmurtština',
	'ug' => 'ujgurština',
	'uga' => 'ugaritština',
	'uk' => 'ukrajinština',
	'umb' => 'umbundu',
	'und' => 'neznámý jazyk',
	'ur' => 'urdština',
	'uz' => 'uzbečtina',
	'vai' => 'vai',
	've' => 'venda',
	'vec' => 'benátština',
	'vep' => 'vepština',
	'vi' => 'vietnamština',
	'vls' => 'vlámština (západní)',
	'vmf' => 'němčina (mohansko-franské dialekty)',
	'vo' => 'volapük',
	'vot' => 'votština',
	'vro' => 'võruština',
	'vun' => 'vunjo',
	'wa' => 'valonština',
	'wae' => 'němčina (walser)',
	'wal' => 'wolajtština',
	'war' => 'warajština',
	'was' => 'waština',
	'wbp' => 'warlpiri',
	'wo' => 'wolofština',
	'wuu' => 'čínština (dialekty Wu)',
	'xal' => 'kalmyčtina',
	'xh' => 'xhoština',
	'xmf' => 'mingrelština',
	'xog' => 'sogština',
	'yao' => 'jaoština',
	'yap' => 'japština',
	'yav' => 'jangbenština',
	'ybb' => 'yemba',
	'yi' => 'jidiš',
	'yo' => 'jorubština',
	'yrl' => 'nheengatu',
	'yue' => 'kantonština',
	'za' => 'čuangština',
	'zap' => 'zapotéčtina',
	'zbl' => 'bliss systém',
	'zea' => 'zélandština',
	'zen' => 'zenaga',
	'zgh' => 'tamazight (standardní marocký)',
	'zh' => 'čínština',
	'zh_Hans' => 'čínština (zjednodušená)',
	'zu' => 'zuluština',
	'zun' => 'zunijština',
	'zxx' => 'žádný jazykový obsah',
	'zza' => 'zaza',
};

is_deeply($locale->all_languages, $all_languages, 'All languages');

is($locale->script_name(), '', 'Script name from current locale');
is($locale->script_name('latn'), 'latinka', 'Script name from string');
is($locale->script_name($other_locale), '', 'Script name from other locale object');

my $all_scripts = {
	'Afak' => 'afaka',
	'Aghb' => 'kavkazskoalbánské',
	'Arab' => 'arabské',
	'Arab@alt=variant' => 'persko-arabské',
	'Armi' => 'aramejské (imperiální)',
	'Armn' => 'arménské',
	'Avst' => 'avestánské',
	'Bali' => 'balijské',
	'Bamu' => 'bamumské',
	'Bass' => 'bassa vah',
	'Batk' => 'batacké',
	'Beng' => 'bengálské',
	'Blis' => 'Blissovo písmo',
	'Bopo' => 'bopomofo',
	'Brah' => 'bráhmí',
	'Brai' => 'Braillovo písmo',
	'Bugi' => 'buginské',
	'Buhd' => 'buhidské',
	'Cakm' => 'čakma',
	'Cans' => 'slabičné písmo kanadských domorodců',
	'Cari' => 'karijské',
	'Cham' => 'čam',
	'Cher' => 'čerokí',
	'Cirt' => 'kirt',
	'Copt' => 'koptské',
	'Cprt' => 'kyperské',
	'Cyrl' => 'cyrilice',
	'Cyrs' => 'cyrilce - staroslověnská',
	'Deva' => 'dévanágárí',
	'Dsrt' => 'deseret',
	'Dupl' => 'Duployého těsnopis',
	'Egyd' => 'egyptské démotické',
	'Egyh' => 'egyptské hieratické',
	'Egyp' => 'egyptské hieroglyfy',
	'Elba' => 'elbasanské',
	'Ethi' => 'etiopské',
	'Geok' => 'gruzínské chutsuri',
	'Geor' => 'gruzínské',
	'Glag' => 'hlaholice',
	'Goth' => 'gotické',
	'Gran' => 'grantha',
	'Grek' => 'řecké',
	'Gujr' => 'gudžarátí',
	'Guru' => 'gurmukhi',
	'Hang' => 'hangul',
	'Hani' => 'han',
	'Hano' => 'hanunóo',
	'Hans' => 'zjednodušené',
	'Hans@alt=stand-alone' => 'han (zjednodušené)',
	'Hant' => 'tradiční',
	'Hant@alt=stand-alone' => 'han (tradiční)',
	'Hebr' => 'hebrejské',
	'Hira' => 'hiragana',
	'Hluw' => 'anatolské hieroglyfy',
	'Hmng' => 'hmongské',
	'Hrkt' => 'japonské slabičné',
	'Hung' => 'staromaďarské',
	'Inds' => 'harappské',
	'Ital' => 'etruské',
	'Java' => 'javánské',
	'Jpan' => 'japonské',
	'Jurc' => 'džürčenské',
	'Kali' => 'kayah li',
	'Kana' => 'katakana',
	'Khar' => 'kháróšthí',
	'Khmr' => 'khmerské',
	'Khoj' => 'chodžiki',
	'Knda' => 'kannadské',
	'Kore' => 'korejské',
	'Kpel' => 'kpelle',
	'Kthi' => 'kaithi',
	'Lana' => 'lanna',
	'Laoo' => 'laoské',
	'Latf' => 'latinka - lomená',
	'Latg' => 'latinka - galská',
	'Latn' => 'latinka',
	'Lepc' => 'lepčské',
	'Limb' => 'limbu',
	'Lina' => 'lineární A',
	'Linb' => 'lineární B',
	'Lisu' => 'Fraserovo',
	'Loma' => 'loma',
	'Lyci' => 'lýkijské',
	'Lydi' => 'lýdské',
	'Mahj' => 'mahádžaní',
	'Mand' => 'mandejské',
	'Mani' => 'manichejské',
	'Maya' => 'mayské hieroglyfy',
	'Mend' => 'mendské',
	'Merc' => 'meroitické psací',
	'Mero' => 'meroitické',
	'Mlym' => 'malajlámské',
	'Modi' => 'modí',
	'Mong' => 'mongolské',
	'Moon' => 'Moonovo',
	'Mroo' => 'mro',
	'Mtei' => 'mejtej majek (manipurské)',
	'Mymr' => 'myanmarské',
	'Narb' => 'staroseveroarabské',
	'Nbat' => 'nabatejské',
	'Nkgb' => 'naxi geba',
	'Nkoo' => 'n’ko',
	'Nshu' => 'nü-šu',
	'Ogam' => 'ogamské',
	'Olck' => 'santálské (ol chiki)',
	'Orkh' => 'orchonské',
	'Orya' => 'urijské',
	'Osma' => 'osmanské',
	'Palm' => 'palmýrské',
	'Pauc' => 'pau cin hau',
	'Perm' => 'staropermské',
	'Phag' => 'phags-pa',
	'Phli' => 'pahlavské klínové',
	'Phlp' => 'pahlavské žalmové',
	'Phlv' => 'pahlavské knižní',
	'Phnx' => 'fénické',
	'Plrd' => 'Pollardova fonetická abeceda',
	'Prti' => 'parthské klínové',
	'Rjng' => 'redžanské',
	'Roro' => 'rongorongo',
	'Runr' => 'runové',
	'Samr' => 'samařské',
	'Sara' => 'sarati',
	'Sarb' => 'starojihoarabské',
	'Saur' => 'saurášterské',
	'Sgnw' => 'SignWriting',
	'Shaw' => 'Shawova abeceda',
	'Shrd' => 'šáradá',
	'Sidd' => 'siddham',
	'Sind' => 'chudábádí',
	'Sinh' => 'sinhálské',
	'Sora' => 'sora sompeng',
	'Sund' => 'sundské',
	'Sylo' => 'sylhetské',
	'Syrc' => 'syrské',
	'Syre' => 'syrské - estrangelo',
	'Syrj' => 'syrské - západní',
	'Syrn' => 'syrské - východní',
	'Tagb' => 'tagbanwa',
	'Takr' => 'takrí',
	'Tale' => 'tai le',
	'Talu' => 'tai lü nové',
	'Taml' => 'tamilské',
	'Tang' => 'tangut',
	'Tavt' => 'tai viet',
	'Telu' => 'telugské',
	'Teng' => 'tengwar',
	'Tfng' => 'berberské',
	'Tglg' => 'tagalské',
	'Thaa' => 'thaana',
	'Thai' => 'thajské',
	'Tibt' => 'tibetské',
	'Tirh' => 'tirhuta',
	'Ugar' => 'ugaritské klínové',
	'Vaii' => 'vai',
	'Visp' => 'viditelná řeč',
	'Wara' => 'varang kšiti',
	'Wole' => 'karolínské (woleai)',
	'Xpeo' => 'staroperské klínové písmo',
	'Xsux' => 'sumero-akkadské klínové písmo',
	'Yiii' => 'yi',
	'Zmth' => 'matematický zápis',
	'Zsym' => 'symboly',
	'Zxxx' => 'bez zápisu',
	'Zyyy' => 'obecné',
	'Zzzz' => 'neznámé písmo',
};

is_deeply($locale->all_scripts, $all_scripts, 'All scripts');

is($locale->territory_name(), 'Česká republika', 'Territory name from current locale');
is($locale->territory_name('fr'), 'Francie', 'Territory name from string');
is($locale->territory_name($other_locale), 'Spojené státy', 'Territory name from other locale object');

my $all_territories = {
	'001' => 'Svět',
	'002' => 'Afrika',
	'003' => 'Severní Amerika',
	'005' => 'Jižní Amerika',
	'009' => 'Oceánie',
	'011' => 'Západní Afrika',
	'013' => 'Střední Amerika',
	'014' => 'Východní Afrika',
	'015' => 'Severní Afrika',
	'017' => 'Střední Afrika',
	'018' => 'Jižní Afrika',
	'019' => 'Amerika',
	'021' => 'Severní Amerika (oblast)',
	'029' => 'Karibik',
	'030' => 'Východní Asie',
	'034' => 'Jižní Asie',
	'035' => 'Jihovýchodní Asie',
	'039' => 'Jižní Evropa',
	'053' => 'Australasie',
	'054' => 'Melanésie',
	'057' => 'Mikronésie (region)',
	'061' => 'Polynésie',
	'142' => 'Asie',
	'143' => 'Střední Asie',
	'145' => 'Západní Asie',
	'150' => 'Evropa',
	'151' => 'Východní Evropa',
	'154' => 'Severní Evropa',
	'155' => 'Západní Evropa',
	'419' => 'Latinská Amerika',
	'AC' => 'Ascension',
	'AD' => 'Andorra',
	'AE' => 'Spojené arabské emiráty',
	'AF' => 'Afghánistán',
	'AG' => 'Antigua a Barbuda',
	'AI' => 'Anguilla',
	'AL' => 'Albánie',
	'AM' => 'Arménie',
	'AN' => 'Nizozemské Antily',
	'AO' => 'Angola',
	'AQ' => 'Antarktida',
	'AR' => 'Argentina',
	'AS' => 'Americká Samoa',
	'AT' => 'Rakousko',
	'AU' => 'Austrálie',
	'AW' => 'Aruba',
	'AX' => 'Ålandy',
	'AZ' => 'Ázerbájdžán',
	'BA' => 'Bosna a Hercegovina',
	'BB' => 'Barbados',
	'BD' => 'Bangladéš',
	'BE' => 'Belgie',
	'BF' => 'Burkina Faso',
	'BG' => 'Bulharsko',
	'BH' => 'Bahrajn',
	'BI' => 'Burundi',
	'BJ' => 'Benin',
	'BL' => 'Svatý Bartoloměj',
	'BM' => 'Bermudy',
	'BN' => 'Brunej',
	'BO' => 'Bolívie',
	'BQ' => 'Karibské Nizozemsko',
	'BR' => 'Brazílie',
	'BS' => 'Bahamy',
	'BT' => 'Bhútán',
	'BV' => 'Bouvetův ostrov',
	'BW' => 'Botswana',
	'BY' => 'Bělorusko',
	'BZ' => 'Belize',
	'CA' => 'Kanada',
	'CC' => 'Kokosové ostrovy',
	'CD' => 'Kongo – Kinshasa',
	'CD@alt=variant' => 'Kongo (DRK)',
	'CF' => 'Středoafrická republika',
	'CG' => 'Kongo – Brazzaville',
	'CG@alt=variant' => 'Kongo (republika)',
	'CH' => 'Švýcarsko',
	'CI' => 'Pobřeží slonoviny',
	'CI@alt=variant' => 'Côte d’Ivoire',
	'CK' => 'Cookovy ostrovy',
	'CL' => 'Chile',
	'CM' => 'Kamerun',
	'CN' => 'Čína',
	'CO' => 'Kolumbie',
	'CP' => 'Clippertonův ostrov',
	'CR' => 'Kostarika',
	'CU' => 'Kuba',
	'CV' => 'Kapverdy',
	'CW' => 'Curaçao',
	'CX' => 'Vánoční ostrov',
	'CY' => 'Kypr',
	'CZ' => 'Česká republika',
	'DE' => 'Německo',
	'DG' => 'Diego García',
	'DJ' => 'Džibutsko',
	'DK' => 'Dánsko',
	'DM' => 'Dominika',
	'DO' => 'Dominikánská republika',
	'DZ' => 'Alžírsko',
	'EA' => 'Ceuta a Melilla',
	'EC' => 'Ekvádor',
	'EE' => 'Estonsko',
	'EG' => 'Egypt',
	'EH' => 'Západní Sahara',
	'ER' => 'Eritrea',
	'ES' => 'Španělsko',
	'ET' => 'Etiopie',
	'EU' => 'Evropská unie',
	'FI' => 'Finsko',
	'FJ' => 'Fidži',
	'FK' => 'Falklandské ostrovy',
	'FK@alt=variant' => 'Falklandské ostrovy (Malvíny)',
	'FM' => 'Mikronésie',
	'FO' => 'Faerské ostrovy',
	'FR' => 'Francie',
	'GA' => 'Gabon',
	'GB' => 'Velká Británie',
	'GB@alt=short' => 'VB',
	'GD' => 'Grenada',
	'GE' => 'Gruzie',
	'GF' => 'Francouzská Guyana',
	'GG' => 'Guernsey',
	'GH' => 'Ghana',
	'GI' => 'Gibraltar',
	'GL' => 'Grónsko',
	'GM' => 'Gambie',
	'GN' => 'Guinea',
	'GP' => 'Guadeloupe',
	'GQ' => 'Rovníková Guinea',
	'GR' => 'Řecko',
	'GS' => 'Jižní Georgie a Jižní Sandwichovy ostrovy',
	'GT' => 'Guatemala',
	'GU' => 'Guam',
	'GW' => 'Guinea-Bissau',
	'GY' => 'Guyana',
	'HK' => 'Hongkong – ZAO Číny',
	'HK@alt=short' => 'Hongkong',
	'HM' => 'Heardův ostrov a McDonaldovy ostrovy',
	'HN' => 'Honduras',
	'HR' => 'Chorvatsko',
	'HT' => 'Haiti',
	'HU' => 'Maďarsko',
	'IC' => 'Kanárské ostrovy',
	'ID' => 'Indonésie',
	'IE' => 'Irsko',
	'IL' => 'Izrael',
	'IM' => 'Ostrov Man',
	'IN' => 'Indie',
	'IO' => 'Britské indickooceánské území',
	'IQ' => 'Irák',
	'IR' => 'Írán',
	'IS' => 'Island',
	'IT' => 'Itálie',
	'JE' => 'Jersey',
	'JM' => 'Jamajka',
	'JO' => 'Jordánsko',
	'JP' => 'Japonsko',
	'KE' => 'Keňa',
	'KG' => 'Kyrgyzstán',
	'KH' => 'Kambodža',
	'KI' => 'Kiribati',
	'KM' => 'Komory',
	'KN' => 'Svatý Kryštof a Nevis',
	'KP' => 'Severní Korea',
	'KR' => 'Jižní Korea',
	'KW' => 'Kuvajt',
	'KY' => 'Kajmanské ostrovy',
	'KZ' => 'Kazachstán',
	'LA' => 'Laos',
	'LB' => 'Libanon',
	'LC' => 'Svatá Lucie',
	'LI' => 'Lichtenštejnsko',
	'LK' => 'Srí Lanka',
	'LR' => 'Libérie',
	'LS' => 'Lesotho',
	'LT' => 'Litva',
	'LU' => 'Lucembursko',
	'LV' => 'Lotyšsko',
	'LY' => 'Libye',
	'MA' => 'Maroko',
	'MC' => 'Monako',
	'MD' => 'Moldavsko',
	'ME' => 'Černá Hora',
	'MF' => 'Svatý Martin (Francie)',
	'MG' => 'Madagaskar',
	'MH' => 'Marshallovy ostrovy',
	'MK' => 'Makedonie',
	'MK@alt=variant' => 'Makedonie (FYROM)',
	'ML' => 'Mali',
	'MM' => 'Myanmar (Barma)',
	'MN' => 'Mongolsko',
	'MO' => 'Macao – ZAO Číny',
	'MO@alt=short' => 'Macao',
	'MP' => 'Severní Mariany',
	'MQ' => 'Martinik',
	'MR' => 'Mauritánie',
	'MS' => 'Montserrat',
	'MT' => 'Malta',
	'MU' => 'Mauricius',
	'MV' => 'Maledivy',
	'MW' => 'Malawi',
	'MX' => 'Mexiko',
	'MY' => 'Malajsie',
	'MZ' => 'Mosambik',
	'NA' => 'Namibie',
	'NC' => 'Nová Kaledonie',
	'NE' => 'Niger',
	'NF' => 'Norfolk',
	'NG' => 'Nigérie',
	'NI' => 'Nikaragua',
	'NL' => 'Nizozemsko',
	'NO' => 'Norsko',
	'NP' => 'Nepál',
	'NR' => 'Nauru',
	'NU' => 'Niue',
	'NZ' => 'Nový Zéland',
	'OM' => 'Omán',
	'PA' => 'Panama',
	'PE' => 'Peru',
	'PF' => 'Francouzská Polynésie',
	'PG' => 'Papua-Nová Guinea',
	'PH' => 'Filipíny',
	'PK' => 'Pákistán',
	'PL' => 'Polsko',
	'PM' => 'Saint-Pierre a Miquelon',
	'PN' => 'Pitcairnovy ostrovy',
	'PR' => 'Portoriko',
	'PS' => 'Palestinská území',
	'PS@alt=short' => 'Palestina',
	'PT' => 'Portugalsko',
	'PW' => 'Palau',
	'PY' => 'Paraguay',
	'QA' => 'Katar',
	'QO' => 'Vnější Oceánie',
	'RE' => 'Réunion',
	'RO' => 'Rumunsko',
	'RS' => 'Srbsko',
	'RU' => 'Rusko',
	'RW' => 'Rwanda',
	'SA' => 'Saúdská Arábie',
	'SB' => 'Šalamounovy ostrovy',
	'SC' => 'Seychely',
	'SD' => 'Súdán',
	'SE' => 'Švédsko',
	'SG' => 'Singapur',
	'SH' => 'Svatá Helena',
	'SI' => 'Slovinsko',
	'SJ' => 'Špicberky a Jan Mayen',
	'SK' => 'Slovensko',
	'SL' => 'Sierra Leone',
	'SM' => 'San Marino',
	'SN' => 'Senegal',
	'SO' => 'Somálsko',
	'SR' => 'Surinam',
	'SS' => 'Jižní Súdán',
	'ST' => 'Svatý Tomáš a Princův ostrov',
	'SV' => 'Salvador',
	'SX' => 'Svatý Martin (Nizozemsko)',
	'SY' => 'Sýrie',
	'SZ' => 'Svazijsko',
	'TA' => 'Tristan da Cunha',
	'TC' => 'Turks a Caicos',
	'TD' => 'Čad',
	'TF' => 'Francouzská jižní území',
	'TG' => 'Togo',
	'TH' => 'Thajsko',
	'TJ' => 'Tádžikistán',
	'TK' => 'Tokelau',
	'TL' => 'Východní Timor',
	'TM' => 'Turkmenistán',
	'TN' => 'Tunisko',
	'TO' => 'Tonga',
	'TR' => 'Turecko',
	'TT' => 'Trinidad a Tobago',
	'TV' => 'Tuvalu',
	'TW' => 'Tchaj-wan',
	'TZ' => 'Tanzanie',
	'UA' => 'Ukrajina',
	'UG' => 'Uganda',
	'UM' => 'Menší odlehlé ostrovy USA',
	'US' => 'Spojené státy',
	'US@alt=short' => 'USA',
	'UY' => 'Uruguay',
	'UZ' => 'Uzbekistán',
	'VA' => 'Vatikán',
	'VC' => 'Svatý Vincenc a Grenadiny',
	'VE' => 'Venezuela',
	'VG' => 'Britské Panenské ostrovy',
	'VI' => 'Americké Panenské ostrovy',
	'VN' => 'Vietnam',
	'VU' => 'Vanuatu',
	'WF' => 'Wallis a Futuna',
	'WS' => 'Samoa',
	'XK' => 'Kosovo',
	'YE' => 'Jemen',
	'YT' => 'Mayotte',
	'ZA' => 'Jihoafrická republika',
	'ZM' => 'Zambie',
	'ZW' => 'Zimbabwe',
	'ZZ' => 'Neznámá oblast',
};

is_deeply($locale->all_territories(), $all_territories, 'All Territories');

is($locale->variant_name('SCOTLAND'), 'angličtina (Skotsko)', 'Variant name from string');

is($locale->key_name('colCaseLevel'), 'Rozlišovaní velkých a malých písmen při řazení', 'Key name from string');

is($locale->type_name(colCaseFirst => 'lower'), 'Nejdříve řadit malá písmena', 'Type name from string');

is($locale->measurement_system_name('metric'), 'metrický', 'Measurement system name English Metric');
is($locale->measurement_system_name('us'), 'USA', 'Measurement system name English US');
is($locale->measurement_system_name('uk'), 'Velká Británie', 'Measurement system name English UK');

is($locale->transform_name('Numeric'), 'Numerický', 'Transform name from string');