package main

import (
    "flag"
    "fmt"
    "log"
    "os"
    "strings"
    "strconv"
	
    "github.com/google/gopacket"
    "github.com/google/gopacket/layers"
    "github.com/google/gopacket/pcap"
)

func main() {
    // Parse CLI arguments in order to get the input and output filenames.
    inputFile := flag.String("input", "", "Input PCAP file")
    outputFile := flag.String("output", "output.txt", "Output text file")
    flag.Parse()

    // Função anônima para iterar pelos arquivos *.pcap
    var visitFile = func(path string, f os.DirEntry, err error) error {
        if err != nil {
            fmt.Printf("Erro ao acessar %q: %v\n", path, err)
            return err
        }
         if !f.IsDir() && strings.HasSuffix(f.Name(), ".pcap") {
            // Open the PCAP file in order to read from it.
            handle, err := pcap.OpenOffline(*path)
            if err != nil {
                log.Fatal(err)
            }
            defer handle.Close()

            dir := filepath.Dir(path)
            newFilePath := filepath.Join(dir, "novo_arquivo.txt")

            // Create the output file.
            output, err := os.Create(newFilePath)
            if err != nil {
                log.Fatal(err)
            }
            defer output.Close()

            // Iterate through the packets in the PCAP file.
            packetSource := gopacket.NewPacketSource(handle, handle.LinkType())
            for packet := range packetSource.Packets() {
                // Initialize relevant stuff.
                ipLayer := packet.Layer(layers.LayerTypeIPv4)
                icmpv4Layer := packet.Layer(layers.LayerTypeICMPv4)
                transportLayer := packet.TransportLayer()

                // Get source IP address.
                var srcIp string
                if ipLayer != nil {
                    srcIp = ipLayer.(*layers.IPv4).SrcIP.String()
                }
                
                // Determine which transport protocol it is, or if it is an ICMP packet.
                var proto string
                var dstPort int
                var srcPort int
                if transportLayer != nil {
                    proto = strings.ToUpper(transportLayer.LayerType().String())
                    dstPort, _ = strconv.Atoi(transportLayer.TransportFlow().Dst().String())
                    srcPort, _ = strconv.Atoi(transportLayer.TransportFlow().Src().String())
                } else if icmpv4Layer != nil {
                    proto = strings.ToUpper(icmpv4Layer.LayerType().String())
                } else {
                    proto = "UNKNOWN"
                }
                
                // The condition below serves as a criteria to ignore packets that may be responses to connections started by the machine itself.
                // Ports >=32768 are typically allocated by Linux as client-side ephemeral ports.
                if((dstPort >= 32768 && (srcPort == 80 || srcPort == 443 || srcPort == 53 || srcPort == 123 || srcPort == 21))) {
                    continue;
                }

                // See if it is a TCP packet and if it has the SYN flag.
                var tcpSyn string
                if proto == "TCP" && transportLayer.(*layers.TCP).SYN {
                    tcpSyn = "IS_TCP_SYN"
                }

                // Write the extracted data to the output text file.
                output.WriteString(fmt.Sprintf("%s %d %s %s\n", srcIp, dstPort, proto, tcpSyn))
            }

            fmt.Printf("Packet data written to %s\n", *outputFile)
        }
        return nil
    }
     // Use filepath.Walk para percorrer recursivamente os diretórios
    err := filepath.Walk(directory, visitFile)
    if err != nil {
        fmt.Printf("Erro ao percorrer o diretório: %v\n", err)
    }
}
